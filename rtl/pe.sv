module pe #(
    parameter int DATA_WIDTH = 8
)(
    input  logic                               clk,
    input  logic                               rst_n,
    input  logic                               clear,
    input  logic signed [DATA_WIDTH-1:0]       left_in,
    input  logic signed [DATA_WIDTH-1:0]       top_in,
    output logic signed [DATA_WIDTH-1:0]       right_out,
    output logic signed [DATA_WIDTH-1:0]       bot_out,
    output logic signed [(2*DATA_WIDTH)+1:0]   acc_out
);

    // Internal registers for data forwarding (systolic flow)
    logic signed [DATA_WIDTH-1:0] r_data;
    logic signed [DATA_WIDTH-1:0] r_weight;
    
    // Accumulator register
    logic signed [(2*DATA_WIDTH)+1:0] r_acc;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_data   <= '0;
            r_weight <= '0;
            r_acc    <= '0;
        end else begin
            // Forward data to neighbors
            r_data   <= left_in;
            r_weight <= top_in;
            
            // Multiply and accumulate (or clear)
            if (clear) begin
                r_acc <= (left_in * top_in);
            end else begin
                r_acc <= r_acc + (left_in * top_in);
            end
        end
    end

    // Assign outputs
    assign right_out = r_data;
    assign bot_out   = r_weight;
    assign acc_out   = r_acc;

endmodule