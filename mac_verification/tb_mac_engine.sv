`timescale 1ns / 1ps

module tb_mac_engine();

    localparam DATA_W = 16;
    localparam ACC_W  = 40;
    localparam CLK_PERIOD = 20;

    logic clk;
    logic rst_n;
    logic s_axis_tvalid;
    logic s_axis_tready;
    logic [31:0] s_axis_tdata;
    logic s_axis_tuser;
    logic m_axis_tvalid;
    logic m_axis_tready;
    logic [ACC_W-1:0] m_axis_tdata;
    logic inject_bubble = 0;

    mac_engine #(.DATA_W(DATA_W), .ACC_W(ACC_W)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tvalid(s_axis_tvalid), .s_axis_tready(s_axis_tready),
        .s_axis_tdata(s_axis_tdata), .s_axis_tuser(s_axis_tuser),
        .m_axis_tvalid(m_axis_tvalid), .m_axis_tready(m_axis_tready),
        .m_axis_tdata(m_axis_tdata)
    );

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        #(CLK_PERIOD * 100000);
        $display("\n[FATAL] TIMEOUT: Pipeline stalled permanently or dropped a vector.");
        $finish;
    end

    int fd_stim, fd_exp;
    int vectors_run = 0;
    int errors = 0;
    logic [ACC_W-1:0] expected_val;

    // ==========================================================
    // THE PHASE-SPLIT VERIFICATION ENGINE
    // ==========================================================
    initial begin
        logic has_data = 0;
        logic [31:0] next_tdata;
        logic next_tuser;
        logic rx_done;
        logic tx_done;

        s_axis_tvalid = 0;
        s_axis_tdata  = 0;
        s_axis_tuser  = 0;
        m_axis_tready = 1;
        rst_n = 0;

        fd_stim = $fopen("stimulus.hex", "r");
        fd_exp  = $fopen("expected.hex", "r");
        if (fd_stim == 0 || fd_exp == 0) $fatal(1, "File Open Error");

        #(CLK_PERIOD * 5);
        @(negedge clk);
        rst_n = 1;

        while (!$feof(fd_exp)) begin
            
            // --------------------------------------------------
            // PHASE 1: EVALUATE HANDSHAKES (At Negedge)
            // Halfway through the cycle, all signals are stable.
            // --------------------------------------------------
            @(negedge clk);

            rx_done = (m_axis_tvalid == 1 && m_axis_tready == 1);
            tx_done = (s_axis_tvalid == 1 && s_axis_tready == 1);

            if (rx_done) begin
                if ($fscanf(fd_exp, "%h\n", expected_val) == 1) begin
                    vectors_run++;
                    if (m_axis_tdata !== expected_val) begin
                        $display("[%0t] MISMATCH [Vector %0d] | Expected: %010h | Got: %010h", 
                                 $time, vectors_run, expected_val, m_axis_tdata);
                        errors++;
                    end
                end
            end

            if (tx_done) begin
                has_data = 0; 
            end

            // --------------------------------------------------
            // PHASE 2: DRIVE NEXT CYCLE (At Posedge + 1ns)
            // Wait for flip-flops to update, then drive new data.
            // --------------------------------------------------
            @(posedge clk);
            #1;

            m_axis_tready = ($urandom_range(0, 100) < 85);
            
                if (has_data == 0 && !$feof(fd_stim)) begin
                    if ($fscanf(fd_stim, "%b %h\n", next_tuser, next_tdata) == 2) begin
                        has_data = 1;
                        // Determine if this specific vector will be preceded by a bubble
                        inject_bubble = ($urandom_range(0, 100) < 20);
                    end
                end

                if (has_data == 1) begin
                    if (inject_bubble) begin
                        s_axis_tvalid = 0; // Legal Bubble Injection
                        inject_bubble = 0; // Only inject one bubble for testing
                    end else begin
                        s_axis_tvalid = 1;
                        s_axis_tdata  = next_tdata;
                        s_axis_tuser  = next_tuser;
                    end
                end else begin
                    s_axis_tvalid = 0;
                end
        end

        $display("\n=======================================");
        $display("SIMULATION COMPLETE");
        $display("Vectors Checked: %0d", vectors_run);
        $display("Errors Found:    %0d", errors);
        if (errors == 0) $display("STATUS: PASSED. ZERO DROPS.");
        else $display("STATUS: FAILED.");
        $display("=======================================\n");
        $finish;
    end
    
    initial begin
        $dumpfile("mac_waves.vcd");
        $dumpvars(0, tb_mac_engine);
    end
endmodule
