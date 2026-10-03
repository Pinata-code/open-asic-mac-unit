`timescale 1ns/1ps

// Self-checking testbench for the processing element (pe.sv).
// A small reference model is updated alongside every clock edge and compared
// against right_out, bot_out and acc_out.
module tb_pe;

    parameter int DATA_WIDTH = 8;
    parameter int ACC_WIDTH  = (2*DATA_WIDTH)+2;
    parameter int CLK_PERIOD = 10;

    // DUT signals
    logic                          clk;
    logic                          rst_n;
    logic                          clear;
    logic signed [DATA_WIDTH-1:0]  left_in;
    logic signed [DATA_WIDTH-1:0]  top_in;
    logic signed [DATA_WIDTH-1:0]  right_out;
    logic signed [DATA_WIDTH-1:0]  bot_out;
    logic signed [ACC_WIDTH-1:0]   acc_out;

    pe #(.DATA_WIDTH(DATA_WIDTH)) dut (
        .clk(clk), .rst_n(rst_n), .clear(clear),
        .left_in(left_in), .top_in(top_in),
        .right_out(right_out), .bot_out(bot_out), .acc_out(acc_out)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

`ifdef WAVES
    initial begin
        $dumpfile("tb_pe.vcd");
        $dumpvars(0, tb_pe);
    end
`endif

    // Reference model state
    logic signed [DATA_WIDTH-1:0] exp_right, exp_bot;
    logic signed [ACC_WIDTH-1:0]  exp_acc;

    int errors = 0;
    int checks = 0;

    // Compare DUT outputs with the model
    task automatic check(input string tag);
        checks++;
        if (right_out !== exp_right || bot_out !== exp_bot || acc_out !== exp_acc) begin
            errors++;
            $display("[FAIL] %s @%0t: right=%0d(exp %0d) bot=%0d(exp %0d) acc=%0d(exp %0d)",
                     tag, $time, right_out, exp_right, bot_out, exp_bot, acc_out, exp_acc);
        end
    endtask

    // Drive one clock cycle: apply inputs away from the clock edge, update the
    // model the way the RTL should behave, then check just after the edge.
    task automatic step(input logic signed [DATA_WIDTH-1:0] l,
                        input logic signed [DATA_WIDTH-1:0] t,
                        input logic c,
                        input string tag);
        @(negedge clk);
        left_in = l;
        top_in  = t;
        clear   = c;
        @(posedge clk);
        // Model: forward inputs, then accumulate / clear
        exp_right = l;
        exp_bot   = t;
        if (c) exp_acc = ACC_WIDTH'(l) * ACC_WIDTH'(t);
        else   exp_acc = exp_acc + ACC_WIDTH'(l) * ACC_WIDTH'(t);
        #1;
        check(tag);
    endtask

    // Asynchronous reset applied between clock edges
    task automatic async_reset(input string tag);
        @(negedge clk);
        #2 rst_n = 0;
        #1;
        exp_right = '0; exp_bot = '0; exp_acc = '0;
        check({tag, " (async, before any clock edge)"});
        @(posedge clk);
        #1;
        check({tag, " (held in reset)"});
        // Release right after the edge so no clock edge occurs before the next step()
        rst_n = 1;
    endtask

    initial begin
        rst_n = 0; clear = 0; left_in = 0; top_in = 0;
        exp_right = '0; exp_bot = '0; exp_acc = '0;

        // 1. Reset state
        repeat (3) @(posedge clk);
        #1 check("reset state");
        @(negedge clk);
        rst_n = 1;

        // 2. Forwarding has one cycle of latency
        step(  5,  -3, 0, "forward 1");
        step( 10,   7, 0, "forward 2");
        step(  0,   0, 0, "forward 3 (zeros, acc holds)");

        // 3. Basic accumulation (clear first so the test is independent of step 2)
        step(  2,   3, 1, "clear -> acc = 6");
        step(  4,   5, 0, "acc += 20");
        step( -1,   6, 0, "acc += -6 (signed)");
        step(  0,  99, 0, "multiply by zero, acc holds");

        // 4. Clear loads the new product (it does not zero the accumulator)
        step(  7,   8, 1, "clear loads 7*8 = 56");
        step(  7,   8, 1, "back-to-back clear stays 56");

        // 5. Signed corner cases
        step(-128, -128, 1, "(-128)*(-128) = 16384");
        step( 127,  127, 0, "+16129");
        step(-128,  127, 0, "-16256");
        step(-128,    1, 0, "-128");
        step( 127, -128, 1, "clear with mixed signs");

        // 6. Asynchronous reset in the middle of operation
        step( 9, 9, 0, "pre-reset accumulate");
        async_reset("reset mid-run");
        step( 3, 4, 0, "after reset: acc = 12");

        // 7. Random regression against the model
        for (int n = 0; n < 500; n++) begin
            // clear often enough to keep the accumulator inside its range
            step($urandom_range(255, 0) - 128,
                 $urandom_range(255, 0) - 128,
                 ($urandom_range(7, 0) == 0),
                 $sformatf("random %0d", n));
        end

        // Summary
        if (errors == 0)
            $display("[TB_PE] PASS: %0d checks, no errors.", checks);
        else
            $display("[TB_PE] FAIL: %0d errors out of %0d checks.", errors, checks);
        $finish;
    end

    // Safety timeout
    initial begin
        #(CLK_PERIOD * 5000);
        $display("[TB_PE] TIMEOUT");
        $finish;
    end

endmodule