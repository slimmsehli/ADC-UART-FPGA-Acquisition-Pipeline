module async_fifo #(
    parameter DATA_WIDTH = 10,
    parameter ADDR_WIDTH = 4 // 2^4 = 16 locations
)(
    // Write Domain (60MHz)
    input  wire                   wclk,
    input  wire                   wrst_n,
    input  wire                   w_en,
    input  wire [DATA_WIDTH-1:0]  wdata,
    output wire                   full,

    // Read Domain (100MHz)
    input  wire                   rclk,
    input  wire                   rrst_n,
    input  wire                   r_en,
    output wire [DATA_WIDTH-1:0]  rdata,
    output wire                   empty
);

    reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];
    reg [ADDR_WIDTH:0] wptr, rptr;
    reg [ADDR_WIDTH:0] wptr_gray_sync1, wptr_gray_sync2;
    reg [ADDR_WIDTH:0] rptr_gray_sync1, rptr_gray_sync2;

    wire [ADDR_WIDTH:0] wptr_gray = (wptr >> 1) ^ wptr;
    wire [ADDR_WIDTH:0] rptr_gray = (rptr >> 1) ^ rptr;

    // --- Write Logic (60MHz) ---
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) wptr <= 0;
        else if (w_en && !full) begin
            mem[wptr[ADDR_WIDTH-1:0]] <= wdata;
            wptr <= wptr + 1;
        end
    end

    // --- Read Logic (100MHz) ---
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) rptr <= 0;
        else if (r_en && !empty) begin
            rptr <= rptr + 1;
        end
    end
    assign rdata = mem[rptr[ADDR_WIDTH-1:0]];

    // --- Synchronizers (The "Secret Sauce") ---
    // Move rptr to wclk domain
    always @(posedge wclk) {rptr_gray_sync2, rptr_gray_sync1} <= {rptr_gray_sync1, rptr_gray};
    // Move wptr to rclk domain
    always @(posedge rclk) {wptr_gray_sync2, wptr_gray_sync1} <= {wptr_gray_sync1, wptr_gray};

    assign full  = (wptr_gray == {~rptr_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1], rptr_gray_sync2[ADDR_WIDTH-2:0]});
    assign empty = (rptr_gray == wptr_gray_sync2);

endmodule
