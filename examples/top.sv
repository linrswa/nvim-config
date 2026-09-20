module top (
    input logic clk,
    input logic rst_n,
    output logic data
);

    always_ff @(posedge clk) begin
        if (!rst_n)
            data <= 1'b0;
        else
            data <= ~data;
    end

endmodule
