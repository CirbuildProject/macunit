`timescale 1ns / 1ps
module tb_mac_engine_3();

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

    mac_engine_2 #(.DATA_W(DATA_W), .ACC_W(ACC_W)) dut (.*);

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ==========================================
    // Clocking Block (Eliminates #1 delays & Race Conditions)
    // Samples 1ns before posedge, drives 1ns after posedge
    // Commented due to clocking block (consequently ##n cycle delays) incompatibility with Icarus Verilog
    // Can be re-enabled if you are using a simulator that supports clocking blocks (e.g., VCS, Questa, etc.)
    // If renabled, use ##n for cycle delays and cb.value for sampling values in the testbench.
    // ==========================================
    //default clocking cb @(posedge clk);
      //  default input #1ns output #1ns;
        //output s_axis_tvalid, s_axis_tdata, s_axis_tuser, m_axis_tready;
        //input  s_axis_tready, m_axis_tvalid, m_axis_tdata;
    //endclocking

    int fd_stim, fd_exp;
    int vectors_run = 0;
    int errors = 0;
    
    // ==========================================
    // Phase-Aware Driver Process (Icarus Compatible)
    // ==========================================
    initial begin
        s_axis_tvalid = 0;
        s_axis_tdata  = 0;
        s_axis_tuser  = 0;
        m_axis_tready = 0;
        rst_n = 0;

        fd_stim = $fopen("stimulus.hex", "r");
        fd_exp  = $fopen("expected.hex", "r");
        if (fd_stim == 0 || fd_exp == 0) $fatal(1, "FATAL: Could not open hex files.");
        
        repeat(5) @(posedge clk); // Wait 5 clock cycles
        #1; rst_n = 1;

        // -----------------------------------------------------------------------
        // TEST CASE 1, 2 & 3: Ideal pipeline, Random Burst Backpressure Stress Test & Upstream Starvation
        // -----------------------------------------------------------------------
        fork
            // TX Thread: Floods data into the module
            begin
                logic [31:0] tdata_in;
                logic user_in;
                $display("Starting Phase 1, 2 & 3: Ideal Throughput, Random Backpressure & Upstream Starvation Test");
                while (!$feof(fd_stim)) begin
                    if ($fscanf(fd_stim, "%b %h\n", user_in, tdata_in) == 2) begin
                        // FIX 2: Drive data immediately (we are already #1 past the clock edge)
                        s_axis_tvalid = 1;
                        s_axis_tdata  = tdata_in;
                        s_axis_tuser  = user_in;
                        
                        // Wait until the clock edge where handshake is successful
                        do begin
                            @(posedge clk);
                        end while (s_axis_tready !== 1'b1);
                        

                        // =======================================
                        // TEST CASE 3: Upstream Starvation
                        // =======================================
                        
                        if ($urandom_range(0, 100) < 10) begin // 10% chance to starve
                            #1; s_axis_tvalid = 0; 
                            repeat($urandom_range(2, 5)) @(posedge clk);
                        end
                        // Step off the clock edge by 1ns so the next loop iteration 
                        // safely changes data without violating hold times.
                        #1; 
                    end
                end
                s_axis_tvalid = 0; // Drop valid when file is empty
            end
            
            // RX Thread: Receives data and randomly triggers BURST stalls
            begin
                logic [ACC_W-1:0] expected_val;
                while (!$feof(fd_exp)) begin
                    
                    // Sample and evaluate handshake safely on the negedge
                    @(negedge clk);
                    if (m_axis_tvalid && m_axis_tready) begin
                        if ($fscanf(fd_exp, "%h\n", expected_val) == 1) begin
                            vectors_run++;
                            if (m_axis_tdata !== expected_val) begin
                                $display("[%0t] MISMATCH! Exp: %010h, Got: %010h", $time, expected_val, m_axis_tdata);
                                errors++;
                            end
                        end
                    end
                    
                    // Wait for posedge to inject random backpressure
                    @(posedge clk); #1;
                    if ($urandom_range(0, 100) < 15) begin
                        m_axis_tready = 0;
                        repeat($urandom_range(2, 10)) @(posedge clk);
                        #1; m_axis_tready = 1;
                    end
                end
            end
        join

        // -----------------------------------------------------
        // TEST CASE 4: Arithmetic Saturation Boundary Stress
        // -----------------------------------------------------
        $display("Starting Phase 4: Saturation Boundary Stress Test");
        @(posedge clk); #1; rst_n = 0; // Hard reset to clear the pipe
        repeat(3) @(posedge clk); #1; rst_n = 1;
        
        m_axis_tready = 1;
        s_axis_tvalid = 1;
        
        // Drive Max Positive x Max Positive (0x7FFF * 0x7FFF = 0x3FFF0001)
        s_axis_tdata = {16'h7FFF, 16'h7FFF}; 
        s_axis_tuser = 0; // Cycle 1: Reset the accumulator with the first product
        
        @(posedge clk); #1;
        s_axis_tuser = 1; // Cycle 2+: Accumulate forever
        
        // It takes ~512 cycles of 0x3FFF0001 to breach 40-bit Max Positive (0x7F_FFFF_FFFF)
        repeat(600) @(posedge clk); 
        
        // Flush the pipeline to observe the final egress data
        #1; s_axis_tvalid = 0;
        repeat(10) @(posedge clk);
        
        // Evaluate the saturation clamp
        if (m_axis_tdata !== 40'h7F_FFFF_FFFF) begin
            $display("[%0t] FATAL: Positive Saturation Failed! Got: %010h", $time, m_axis_tdata);
            errors++;
        end else begin
            $display("[%0t] Positive Saturation Passed. Clamped strictly to %010h", $time, m_axis_tdata);
        end

        // -----------------------------------------------------
        // TEST CASE 5: 100% Throughput Test (No Backpressure)
        // -----------------------------------------------------
        rst_n = 0;
        repeat(5) @(posedge clk); // Wait 5 clock cycles
        #1; rst_n = 1;
        $display("Starting Phase 5: 100%% Throughput Test");
        @(posedge clk); #1;
        m_axis_tready = 1;  

        fd_stim = $fopen("stimulus.hex", "r");
        fd_exp  = $fopen("expected.hex", "r");
        if (fd_stim == 0 || fd_exp == 0) $fatal(1, "FATAL: Could not open hex files.");

        fork
            // TX Thread: Floods data into the module
            begin
                logic [31:0] tdata_in;
                logic user_in;
                while (!$feof(fd_stim)) begin
                    if ($fscanf(fd_stim, "%b %h\n", user_in, tdata_in) == 2) begin
                        s_axis_tvalid = 1;
                        s_axis_tdata  = tdata_in;
                        s_axis_tuser  = user_in;
                        
                        // Wait until the clock edge where handshake is successful
                        do begin
                            @(posedge clk);
                        end while (s_axis_tready !== 1'b1);
                        // Step off the clock edge by 1ns so the next loop iteration 
                        // safely changes data without violating hold times.
                        #1; 
                    end
                end
                s_axis_tvalid = 0; // Drop valid when file is empty
            end
            
            // RX Thread: Receives data and randomly triggers BURST stalls
            begin
                logic [ACC_W-1:0] expected_val;
                while (!$feof(fd_exp)) begin
                    
                    // Sample and evaluate handshake safely on the negedge
                    @(negedge clk);
                    if (m_axis_tvalid && m_axis_tready) begin
                        if ($fscanf(fd_exp, "%h\n", expected_val) == 1) begin
                            vectors_run++;
                            if (m_axis_tdata !== expected_val) begin
                                $display("[%0t] MISMATCH! Exp: %010h, Got: %010h", $time, expected_val, m_axis_tdata);
                                errors++;
                            end
                        end
                    end
                end
            end
        join

        $display("\n=======================================");
        $display("SIMULATION COMPLETE");
        $display("Vectors Checked: %0d", vectors_run);
        $display("Errors Found:    %0d", errors);
        if (errors == 0) $display("STATUS: PASSED.");
        else $display("STATUS: FAILED.");
        $display("=======================================\n");
        $finish;
    end
    
    // Fix: Correct module name scope for waveform dumping
    initial begin
        $dumpfile("mac_waves.vcd");
        $dumpvars(0, tb_mac_engine_3);
    end
endmodule
