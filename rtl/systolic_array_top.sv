//using '#' to introduce parameter port list
module systolic_array_top #(
    parameter int DATA_WIDTH = 8,
    parameter int ARRAY_N    = 4
)(
    input  logic                               clk,
    input  logic                               rst_n,
    input  logic                               clear,
    // Flattened (packed) ports: element k lives at [k*W +: W]
    input  logic [ARRAY_N*DATA_WIDTH-1:0]      row_in_flat,
    input  logic [ARRAY_N*DATA_WIDTH-1:0]      col_in_flat,
    input  logic                               valid_in,
    // Element [r][c] lives at [(r*ARRAY_N+c)*ACC_W +: ACC_W]
    output logic [ARRAY_N*ARRAY_N*((2*DATA_WIDTH)+$clog2(ARRAY_N))-1:0] row_out_flat,
    output logic                               valid_out
);

    localparam int ACC_W = (2*DATA_WIDTH)+$clog2(ARRAY_N);

    // pe_data[i][j]   : data flowing horizontally
    // pe_weight[i][j] : data/weights flowing vertically
    wire signed [DATA_WIDTH-1:0] pe_data   [ARRAY_N][ARRAY_N+1];
    wire signed [DATA_WIDTH-1:0] pe_weight [ARRAY_N+1][ARRAY_N];
    wire signed [ACC_W-1:0]      pe_acc    [ARRAY_N][ARRAY_N];

    genvar i, j;

    generate
        for (i = 0; i < ARRAY_N; i++) begin : gen_row_inputs
            assign pe_data[i][0] = row_in_flat[i*DATA_WIDTH +: DATA_WIDTH];
        end

        for (j = 0; j < ARRAY_N; j++) begin : gen_col_inputs
            assign pe_weight[0][j] = col_in_flat[j*DATA_WIDTH +: DATA_WIDTH];
        end

        for (i = 0; i < ARRAY_N; i++) begin : gen_row_pe
            for (j = 0; j < ARRAY_N; j++) begin : gen_col_pe
                pe #(
                    .DATA_WIDTH(DATA_WIDTH)
                ) u_pe (
                    .clk(clk),
                    .rst_n(rst_n),
                    .clear(clear),
                    .left_in(pe_data[i][j]),
                    .top_in(pe_weight[i][j]),
                    .right_out(pe_data[i][j+1]),
                    .bot_out(pe_weight[i+1][j]),
                    .acc_out(pe_acc[i][j])
                );

                assign row_out_flat[(i*ARRAY_N+j)*ACC_W +: ACC_W] = pe_acc[i][j];
            end
        end
    endgenerate

    // Valid pipeline tracking latency through the array
    logic [(2*ARRAY_N-2):0] valid_pipe;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_pipe <= '0;
        end else begin
            valid_pipe <= {valid_pipe[(2*ARRAY_N-3):0], valid_in};
        end
    end

    assign valid_out = valid_pipe[(2*ARRAY_N-2)];

endmodule