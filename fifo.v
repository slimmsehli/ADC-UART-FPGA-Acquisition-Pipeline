module async_fifo #(parameter DATA_WIDTH = 10, ADDR_WIDTH = 4) (
    input  wire wclk, wrst_n, w_en,
    input  wire [DATA_WIDTH-1:0] wdata,
    input  wire rclk, rrst_n, r_en,
    output reg  [DATA_WIDTH-1:0] rdata,
    output wire full, empty
);
    reg [DATA_WIDTH-1:0] mem [(1<<ADDR_WIDTH)-1:0];
    reg [ADDR_WIDTH:0] wptr, rptr; // Gray coded pointers

    // Write Logic
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) wptr <= 0;
        else if (w_en && !full) begin
            mem[wptr[ADDR_WIDTH-1:0]] <= wdata;
            wptr <= wptr + 1;
        end
    end

    // Read Logic
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) rptr <= 0;
        else if (r_en && !empty) begin
            rdata <= mem[rptr[ADDR_WIDTH-1:0]];
            rptr <= rptr + 1;
        end
    end
    
    assign empty = (wptr == rptr);
    // (Simplified logic for demonstration; real async FIFOs need 2-stage synchronizers)
endmodule
