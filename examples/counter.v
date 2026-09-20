module counter (
    input wire clk,
    input wire rst_n,
    output reg [7:0] count
);

always @(posedge clk) begin
    if (!rst_n)
        count <= 8'd0;
    else
        count <= count + 1'b1;
end

endmodule
