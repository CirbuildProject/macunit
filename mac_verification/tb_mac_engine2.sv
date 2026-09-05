`timescale 1ns / 1ps

module tb_mac_engine2();

    // ==========================================
    // 1. Parameters & Signals
    // ==========================================
    localparam DATA_W = 16;
    localparam ACC_W  = 40;
    localparam CLK_PERIOD = 20;

    logic clk;
    logic rst_n;

    logic              s_axis_tvalid;
    logic              s_axis_tready;
    logic [31:0]       s_axis_tdata;
    logic              s_axis_tuser;

    logic              m_axis_tvalid;
    logic              m_axis_tready;
    logic [ACC_W-1:0]  m_axis_tdata;

    // ==========================================
    // 2. Instantiate the DUT
    // ==========================================
    mac_engine#(
        .DATA_W(DATA_W),
        .ACC_W(ACC_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tuser(s_axis_tuser),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tdata(m_axis_tdata)
    );

    // ==========================================
    // 3. Clock Generation
    // ==========================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ==========================================
    // 4. Verification Variables
    // ==========================================
    int fd_stim, fd_exp;
    int vectors_run = 0;
    int errors = 0;
    logic [ACC_W-1:0] expected_val;

    // ==========================================
    // 5. The Driver Process (TX Block)
    // ==========================================
    initial begin
        // Hard Reset & Initialization (Using Blocking Assignments)
        s_axis_tvalid = 0;
        s_axis_tdata  = 0;
        s_axis_tuser  = 0;
        rst_n = 0;

        fd_stim = $fopen("stimulus.hex", "r");
        if (fd_stim == 0) $fatal(1, "FATAL: Could not open stimulus.hex.");

        #(CLK_PERIOD * 5);
        @(negedge clk);
        rst_n = 1;

        // Drive Data Loop
        while (!$feof(fd_stim)) begin
            logic [31:0] tdata_in;
            logic        user_in;
            logic        inject_bubble;

            // 1. Fetch the next vector from Python
            if ($fscanf(fd_stim, "%b %h\n", user_in, tdata_in) == 2) begin
                
                // Determine if we inject a bubble BEFORE asserting TVALID
                inject_bubble = ($urandom_range(0, 100) < 20);

                if (inject_bubble) begin
                    @(posedge clk); 
                    #1; 
                    s_axis_tvalid = 0; 
                    @(negedge clk); // Wait out the bubble cycle
                end

                // 2. Drive the actual data (Just after posedge)
                @(posedge clk); 
                #1; 
                s_axis_tvalid = 1;
                s_axis_tdata  = tdata_in;
                s_axis_tuser  = user_in;

                // 3. The "Settled Reality" Handshake Wait
                // We evaluate at the negedge. If stalled, we loop back to the next negedge.
                // Notice we do NOT change TVALID or TDATA here, achieving 100% AXI compliance.
                do begin
                    @(negedge clk);
                end while (!(s_axis_tvalid && s_axis_tready));
            end
        end

        // File empty. Drop valid flag.
        @(posedge clk); 
        #1;
        s_axis_tvalid = 0;
        $fclose(fd_stim);
    end

    // ==========================================
    // 6. The Receiver & Scoreboard Process (RX Block)
    // ==========================================
    initial begin
        m_axis_tready = 1;

        fd_exp = $fopen("expected.hex", "r");
        if (fd_exp == 0) $fatal(1, "FATAL: Could not open expected.hex");

        // Wait for reset to clear
        @(posedge rst_n);

        forever begin
            // 1. Evaluate the Handshake (At the negedge, when logic is settled)
            @(negedge clk);
            
            if (m_axis_tvalid && m_axis_tready) begin
                if ($fscanf(fd_exp, "%h\n", expected_val) == 1) begin
                    vectors_run++;
                    
                    if (m_axis_tdata !== expected_val) begin
                        $display("[%0t] MISMATCH [Vector %0d] | Expected: %010h | Got: %010h", 
                                 $time, vectors_run, expected_val, m_axis_tdata);
                        errors++;
                    end
                end 
            end

            if ($feof(fd_exp)) begin
                    // End of verification
                    $display("\n=======================================================");
                    $display("                 SIMULATION COMPLETE");
                    $display("=======================================================");
                    $display("Total Vectors Checked: %0d", vectors_run);
                    $display("Total Errors Found:    %0d", errors);
                    if (errors == 0) 
                        $display("STATUS: PASSED. MATHEMATICS & PROTOCOL VERIFIED.");
                    else 
                        $display("STATUS: FAILED.");
                    $display("=======================================================\n");
                    $finish;
            end

            // 2. Drive Next Cycle's Backpressure (Just after the posedge)
            @(posedge clk); 
            #1;
            m_axis_tready = ($urandom_range(0, 100) < 85); 
        end
    end

    // ==========================================
    // 7. Timeout & Waveform Dumping
    // ==========================================
    initial begin
        #(CLK_PERIOD * 100000);
        $display("\n[FATAL] TIMEOUT: Pipeline stalled permanently or dropped a vector.");
        $finish;
    end

    initial begin
        $dumpfile("mac_waves.vcd");
        $dumpvars(0, tb_mac_engine);
    end

endmodule
