// Hardware-friendly wrapper around systolic_array_top.
//
//  * Replaces the ARRAY_N*ARRAY_N*ACC_W-bit result bus with a small read port:
//    drive rd_addr (row-major index r*ARRAY_N + c) and read rd_data one clock
//    later.
//  * Provides a clean, sticky `done` flag ("all accumulators are final")
//    instead of relying on the valid_out pulse.
//
// Typical use:
//   1. (optional) pulse `clear` for one cycle while the inputs are zero and the
//      array is idle -> zeroes all accumulators.
//   2. Hold valid_in high while streaming the skewed inputs.
//   3. Wait for `done`, then sweep rd_addr to read the results.
module systolic_array_hw #(
    parameter int DATA_WIDTH = 8,
    parameter int ARRAY_N    = 4
)(
    input  logic                                   clk,
    input  logic                                   rst_n,
    input  logic                                   clear,

    // Skewed operand streams, element k at [k*DATA_WIDTH +: DATA_WIDTH]
    input  logic [ARRAY_N*DATA_WIDTH-1:0]          row_in_flat,
    input  logic [ARRAY_N*DATA_WIDTH-1:0]          col_in_flat,
    input  logic                                   valid_in,

    // Status
    output logic                                   busy,   // streaming or draining
    output logic                                   done,   // results final; sticky until next valid_in

    // Result read port (1-cycle latency)
    input  logic [$clog2(ARRAY_N*ARRAY_N)-1:0]     rd_addr,
    output logic signed [(2*DATA_WIDTH)+$clog2(ARRAY_N)-1:0] rd_data
);

    localparam int ACC_W = (2*DATA_WIDTH)+$clog2(ARRAY_N);

    logic [ARRAY_N*ARRAY_N*ACC_W-1:0] results_flat;

    // valid_out is intentionally unused (done/busy replace it)
    /* verilator lint_off PINCONNECTEMPTY */
    systolic_array_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .ARRAY_N(ARRAY_N)
    ) u_core (
        .clk         (clk),
        .rst_n       (rst_n),
        .clear       (clear),
        .row_in_flat (row_in_flat),
        .col_in_flat (col_in_flat),
        .valid_in    (valid_in),
        .row_out_flat(results_flat),
        .valid_out   ()   // replaced by done/busy below
    );
    /* verilator lint_on PINCONNECTEMPTY */

    // ---------------------------------------------------------------
    // busy / done tracking
    // The last operand enters the array on the final valid_in cycle and needs
    // up to ARRAY_N-1 further cycles to reach the far PE, so keep `busy` high
    // for ARRAY_N extra cycles (one cycle of margin) after valid_in falls.
    // ---------------------------------------------------------------
    logic [ARRAY_N-1:0] drain;
    logic               busy_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            drain  <= '0;
            busy_q <= 1'b0;
            done   <= 1'b0;
        end else begin
            drain  <= {drain[ARRAY_N-2:0], valid_in};
            busy_q <= busy;
            if (valid_in)
                done <= 1'b0;          // new run started
            else if (busy_q && !busy)
                done <= 1'b1;          // run finished and pipeline drained
        end
    end

    assign busy = valid_in | (|drain);

    // ---------------------------------------------------------------
    // Registered read mux
    // ---------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rd_data <= '0;
        else
            rd_data <= results_flat[rd_addr*ACC_W +: ACC_W];
    end

endmodule