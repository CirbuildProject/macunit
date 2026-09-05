`timescale 1ns / 1ps
// ==========================================
// AXI4-Stream Skid Buffer (Decouples Backpressure)
// ==========================================
module axi_skid_buffer #(
    parameter WIDTH = 40
)(
    input  logic             clk,
    input  logic             rst_n,
    
    // Upstream (From MAC Stage 3)
    input  logic             s_valid,
    output logic             s_ready,
    input  logic [WIDTH-1:0] s_data,
    
    // Downstream (To Outside World)
    output logic             m_valid,
    input  logic             m_ready,
    output logic [WIDTH-1:0] m_data
);

    logic [WIDTH-1:0] main_reg, skid_reg;
    logic [1:0] state; // 0: Empty, 1: Busy, 2: Full (Skid)

    assign m_valid = (state != 0);
    assign s_ready = (state != 2);
    assign m_data  = main_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= 0;
            main_reg <= '0;
            skid_reg <= '0;
        end else begin
            case (state)
                0: begin // Empty
                    if (s_valid) begin
                        main_reg <= s_data;
                        state <= 1;
                    end
                end
                1: begin // Busy (Normal Pipeline Operation)
                    if (m_ready && s_valid) begin
                        main_reg <= s_data;
                    end else if (m_ready && !s_valid) begin
                        state <= 0;
                    end else if (!m_ready && s_valid) begin
                        skid_reg <= s_data; // Absorb the stall
                        state <= 2;
                    end
                end
                2: begin // Full (Skid Buffer Active)
                    if (m_ready) begin
                        main_reg <= skid_reg;
                        state <= 1;
                    end
                end
            endcase
        end
    end
endmodule
