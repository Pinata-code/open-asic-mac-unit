`timescale 1ns/1ps

// Self-checking testbench for systolic_array_hw.
//  - Generates correctly skewed operand streams for C = A x B
//  - Waits for `done`, reads every result through the rd_addr/rd_data port
//  - Compares against a software reference
//  - Runs several matrices back-to-back, using a one-cycle `clear` between runs
module tb_systolic_array_hw;

    parameter int DATA_WIDTH = 8;
    parameter int ARRAY_N    = 4;
    parameter int CLK_PERIOD = 10;
    localparam int ACC_W     = (2*DATA_WIDTH)+$clog2(ARRAY_N);
    localparam int ADDR_W    = $clog2(ARRAY_N*ARRAY_N);

    logic                                  clk;
    logic                                  rst_n;
    logic                                  clear;
    logic [ARRAY_N*DATA_WIDTH-1:0]         row_in_flat;
    logic [ARRAY_N*DATA_WIDTH-1:0]         col_in_flat;
    logic                                  valid_in;
    logic                                  busy;
    logic                                  done;
    logic [ADDR_W-1:0]                     rd_addr;
    logic signed [ACC_W-1:0]               rd_data;

    systolic_array_hw #(
        .DATA_WIDTH(DATA_WIDTH),
        .ARRAY_N(ARRAY_N)
    ) dut (
        .clk(clk), .rst_n(rst_n), .clear(clear),
        .row_in_flat(row_in_flat), .col_in_flat(col_in_flat),
        .valid_in(valid_in),
        .busy(busy), .done(done),
        .rd_addr(rd_addr), .rd_data(rd_data)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

`ifdef WAVES
    initial begin
        $dumpfile("tb_systolic_array_hw.vcd");
        $dumpvars(0, tb_systolic_array_hw);
    end
`endif

    // Matrices and results
    int A   [ARRAY_N][ARRAY_N];
    int B   [ARRAY_N][ARRAY_N];
    int EXP [ARRAY_N][ARRAY_N];
    int GOT [ARRAY_N][ARRAY_N];

    int errors = 0;
    int runs   = 0;

    // Software reference
    task automatic compute_expected();
        for (int i = 0; i < ARRAY_N; i++)
            for (int j = 0; j < ARRAY_N; j++) begin
                EXP[i][j] = 0;
                for (int k = 0; k < ARRAY_N; k++)
                    EXP[i][j] += A[i][k] * B[k][j];
            end
    endtask

    // Zero the accumulators: a single clear cycle with all-zero inputs and an
    // idle (flushed) array makes every PE load 0*0.
    task automatic clear_array();
        @(negedge clk);
        row_in_flat = '0;
        col_in_flat = '0;
        valid_in    = 1'b0;
        clear       = 1'b1;
        @(negedge clk);
        clear       = 1'b0;
    endtask

    // Stream the skewed operands.
    // At cycle t:  row i carries A[i][t-i],  column j carries B[t-j][j]
    // (zero outside 0 <= k < ARRAY_N).  Total length = 2*ARRAY_N-1 cycles.
    task automatic stream_matrices();
        int k;
        for (int t = 0; t < 2*ARRAY_N-1; t++) begin
            @(negedge clk);
            valid_in = 1'b1;
            for (int i = 0; i < ARRAY_N; i++) begin
                k = t - i;
                row_in_flat[i*DATA_WIDTH +: DATA_WIDTH] =
                    (k >= 0 && k < ARRAY_N) ? DATA_WIDTH'(A[i][k]) : '0;
            end
            for (int j = 0; j < ARRAY_N; j++) begin
                k = t - j;
                col_in_flat[j*DATA_WIDTH +: DATA_WIDTH] =
                    (k >= 0 && k < ARRAY_N) ? DATA_WIDTH'(B[k][j]) : '0;
            end
        end
        @(negedge clk);
        valid_in    = 1'b0;
        row_in_flat = '0;
        col_in_flat = '0;
    endtask

    // Sweep rd_addr and capture results (1-cycle read latency)
    task automatic read_results();
        for (int a = 0; a < ARRAY_N*ARRAY_N; a++) begin
            @(negedge clk);
            rd_addr = ADDR_W'(a);
            @(negedge clk);   // data for rd_addr is valid after one posedge
            GOT[a / ARRAY_N][a % ARRAY_N] = int'($signed(rd_data));
        end
    endtask

    // One complete run
    task automatic run_test(input string name);
        int wait_cycles;
        compute_expected();
        clear_array();
        stream_matrices();

        // done must not be high while busy, and must arrive in bounded time
        wait_cycles = 0;
        while (!done && wait_cycles < 50) begin
            @(posedge clk);
            if (done && busy) begin
                errors++;
                $display("[FAIL] %s: done and busy both high", name);
            end
            wait_cycles++;
        end
        if (!done) begin
            errors++;
            $display("[FAIL] %s: done never asserted", name);
        end

        read_results();

        runs++;
        for (int i = 0; i < ARRAY_N; i++)
            for (int j = 0; j < ARRAY_N; j++)
                if (GOT[i][j] !== EXP[i][j]) begin
                    errors++;
                    $display("[FAIL] %s: C[%0d][%0d] = %0d, expected %0d",
                             name, i, j, GOT[i][j], EXP[i][j]);
                end
        $display("[TB_HW] %s done after %0d wait cycles; C =", name, wait_cycles);
        for (int i = 0; i < ARRAY_N; i++) begin
            $write("   ");
            for (int j = 0; j < ARRAY_N; j++) $write("%8d", GOT[i][j]);
            $write("\n");
        end
    endtask

    initial begin
        rst_n = 0; clear = 0; valid_in = 0; rd_addr = '0;
        row_in_flat = '0; col_in_flat = '0;
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // Test 1: small known values, A = [1..16], B = identity
        for (int i = 0; i < ARRAY_N; i++)
            for (int j = 0; j < ARRAY_N; j++) begin
                A[i][j] = i*ARRAY_N + j + 1;
                B[i][j] = (i == j) ? 1 : 0;
            end
        run_test("A x I (expect A)");

        // Test 2: simple hand-checkable matrices, back-to-back without reset
        for (int i = 0; i < ARRAY_N; i++)
            for (int j = 0; j < ARRAY_N; j++) begin
                A[i][j] = i + 1;
                B[i][j] = j + 1;
            end
        run_test("A[i][k]=i+1, B[k][j]=j+1");

        // Test 3: signed extremes
        for (int i = 0; i < ARRAY_N; i++)
            for (int j = 0; j < ARRAY_N; j++) begin
                A[i][j] = (i + j) % 2 ? -128 : 127;
                B[i][j] = (i * j) % 2 ? -128 : 127;
            end
        run_test("signed extremes");

        // Tests 4-8: random matrices
        for (int n = 0; n < 5; n++) begin
            for (int i = 0; i < ARRAY_N; i++)
                for (int j = 0; j < ARRAY_N; j++) begin
                    A[i][j] = $urandom_range(255, 0) - 128;
                    B[i][j] = $urandom_range(255, 0) - 128;
                end
            run_test($sformatf("random %0d", n));
        end

        if (errors == 0)
            $display("[TB_HW] PASS: %0d runs, all results match A x B.", runs);
        else
            $display("[TB_HW] FAIL: %0d errors over %0d runs.", errors, runs);
        $finish;
    end

    initial begin
        #(CLK_PERIOD * 20000);
        $display("[TB_HW] TIMEOUT");
        $finish;
    end

endmodule