`timescale 1ns / 1ps
// ==========================================
// Pipelined MAC Engine (Top)
// ==========================================
module mac_engine #(
    parameter DATA_W = 16,
    parameter ACC_W  = 40
)(
    input  logic              clk,
    input  logic              rst_n,

    // AXI4-Stream Slave Interface (Input)
    input  logic              s_axis_tvalid,
    output logic              s_axis_tready,
    input  logic [DATA_W*2-1:0] s_axis_tdata,  
    input  logic              s_axis_tuser,  

    // AXI4-Stream Master Interface (Output)
    output logic              m_axis_tvalid,
    input  logic              m_axis_tready,
    output logic [ACC_W-1:0]  m_axis_tdata
);
    // ==========================================
    // Internal Signals bridging MAC and Skid Buffer
    // ==========================================
    logic             mac_valid_out;
    logic             mac_ready_in;
    logic [ACC_W-1:0] mac_data_out;
    // ==========================================
    // 0. Global Pipeline Control (Backpressure)
    // ==========================================
    logic pipe_en;
    
    assign pipe_en = !mac_valid_out || mac_ready_in;
    assign s_axis_tready = pipe_en && rst_n;

    // ==========================================
    // Stage 1: Fetch & Decode Registers
    // ==========================================
    logic signed [DATA_W-1:0] stg1_op_a;
    logic signed [DATA_W-1:0] stg1_op_b;
    logic                     stg1_acc_flag;
    logic                     stg1_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stg1_valid    <= 1'b0;
            stg1_op_a     <= '0;
            stg1_op_b     <= '0;
            stg1_acc_flag <= 1'b0;
        end else if (pipe_en) begin
            if (s_axis_tvalid && s_axis_tready) begin
                stg1_valid    <= 1'b1;
                // Parameterized slicing for clean linting
                stg1_op_a     <= $signed(s_axis_tdata[DATA_W-1:0]);
                stg1_op_b     <= $signed(s_axis_tdata[DATA_W*2-1:DATA_W]);
                stg1_acc_flag <= s_axis_tuser;
            end else begin
                stg1_valid    <= 1'b0; 
            end
        end
    end

    // ==========================================
    // Stage 2: Execute (Multiply) Registers
    // ==========================================
    logic signed [DATA_W*2-1:0] stg2_product;
    logic                       stg2_acc_flag;
    logic                       stg2_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stg2_valid    <= 1'b0;
            stg2_product  <= '0;
            stg2_acc_flag <= 1'b0;
        end else if (pipe_en) begin
            stg2_valid    <= stg1_valid;
            stg2_acc_flag <= stg1_acc_flag;
            
            if (stg1_valid) begin
                stg2_product <= stg1_op_a * stg1_op_b;
            end
        end
    end

    // ==========================================
    // Stage 3: Accumulate & Saturate
    // ==========================================
    logic signed [ACC_W-1:0] stg3_acc_reg;
    logic                    stg3_valid;
    logic signed [ACC_W-1:0] ext_product;
    logic signed [ACC_W-1:0] next_acc;
    logic                    overflow;
    logic                    underflow;

    // Bulletproof explicit sign extension to prevent C++ coercion bugs
    assign ext_product = $signed({ {(ACC_W-DATA_W*2){stg2_product[DATA_W*2-1]}}, stg2_product });
    assign next_acc = stg3_acc_reg + ext_product;

    assign overflow  = (stg3_acc_reg[ACC_W-1] == 1'b0) && (ext_product[ACC_W-1] == 1'b0) && (next_acc[ACC_W-1] == 1'b1);
    assign underflow = (stg3_acc_reg[ACC_W-1] == 1'b1) && (ext_product[ACC_W-1] == 1'b1) && (next_acc[ACC_W-1] == 1'b0);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stg3_valid   <= 1'b0;
            stg3_acc_reg <= '0;
        end else if (pipe_en) begin
            stg3_valid <= stg2_valid;
            
            if (stg2_valid) begin
                if (stg2_acc_flag == 1'b0) begin
                    stg3_acc_reg <= ext_product;
                end else begin
                    if (overflow) begin
                        stg3_acc_reg <= {1'b0, {(ACC_W-1){1'b1}}}; // Max Positive
                    end else if (underflow) begin
                        stg3_acc_reg <= {1'b1, {(ACC_W-1){1'b0}}}; // Max Negative
                    end else begin
                        stg3_acc_reg <= next_acc;
                    end
                end
            end
        end
    end

    assign mac_valid_out = stg3_valid;
    assign mac_data_out  = stg3_acc_reg;

    //Instantiate Skid Buffer to decouple backpressure from MAC
    axi_skid_buffer #(.WIDTH(ACC_W)) u_skid (
        .clk(clk),
        .rst_n(rst_n),
        .s_valid(mac_valid_out),
        .s_ready(mac_ready_in),   // Skid buffer tells MAC if it can accept data
        .s_data(mac_data_out),
        .m_valid(m_axis_tvalid),
        .m_ready(m_axis_tready),
        .m_data(m_axis_tdata)
    );

    // ==========================================
    // Hardware Assertions (Simulation Only)
    // ==========================================
    // synthesis translate_off
    `ifndef __ICARUS__
    // 1. AXI Protocol Defense: Master must not change data while stalled
    property p_axi_data_stable;
        /* verilator lint_off SYNCASYNCNET */
        @(posedge clk) disable iff (!rst_n)
        /* verilator lint_off SYNCASYNCNET */
        (s_axis_tvalid && !s_axis_tready) |=> ($stable(s_axis_tdata) && $stable(s_axis_tuser) && s_axis_tvalid);
    endproperty
    assert_axi_data_stable: assert property (p_axi_data_stable) 
        else $error("SVA FAULT: Master changed s_axis_tdata or dropped TVALID while stalled!");

    // 2. Datapath Defense: Accumulator must never enter an unknown (X) state
    property p_no_x_acc;
        /* verilator lint_off SYNCASYNCNET */
        @(posedge clk) disable iff (!rst_n)
        /* verilator lint_off SYNCASYNCNET */
        !$isunknown(stg3_acc_reg);
    endproperty
    assert_no_x_acc: assert property (p_no_x_acc) 
        else $fatal("SVA FATAL: Accumulator entered X-state. Simulation terminated.");

    // 3. Control Defense: Valid signals cannot be unknown
    property p_no_x_control;
        /* verilator lint_off SYNCASYNCNET */
        @(posedge clk) disable iff (!rst_n)
        /* verilator lint_off SYNCASYNCNET */
        !$isunknown({s_axis_tvalid, m_axis_tvalid});
    endproperty
    assert_no_x_control: assert property (p_no_x_control) 
        else $error("SVA FAULT: AXI TVALID signal is X!");
    `endif
    // synthesis translate_on
endmodule
