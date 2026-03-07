

module uart_decoder_top (
    input  wire        clk,
    input  wire        rst_n,
    // Configuration Registers
    input  wire [15:0] clks_per_bit, // Set this to (Freq/Baud)
    // Physical Lines
    input  wire        uart_rx,
    output reg         uart_tx,
    // Internal Interface
    output reg  [7:0]  rx_byte_out,
    output reg         rx_done_tick,
    input  wire [7:0]  tx_byte_in,
    input  wire        tx_start,
		
		// decoder output
    output wire         cmd_acquire,  // High for 1 cycle on "acquire"
    output wire         cmd_read      // High for 1 cycle on "read"
);
		
		// =========================================================================
    // CLI decoder
    // =========================================================================
    
    uart uart_i (
		  .clk(clk), //input  wire        clk,
		  .rst_n(rst_n), //input  wire        rst_n,
		  // Configuration Registers
		  .clks_per_bit(clks_per_bit), //input  wire [15:0] clks_per_bit(baudrate),
		  // Physical Lines
		  .uart_rx(uart_rx),
		  .uart_tx(uart_tx),
		  // Internal Interface
		  .rx_byte_out(rx_byte_out), //output reg  [7:0]  rx_byte_out,
		  .rx_done_tick(rx_done_tick), //output reg         rx_done_tick,
		  .tx_byte_in(tx_byte_in), //input  wire [7:0]  tx_byte_in,
		  .tx_start(tx_start) //input  wire        tx_start
		);
		
		// Monitor the Output
    always @(posedge clk) begin
        if (rx_done_tick) begin
        	`print("UART", $sformatf("Received Flag High! Data on Bus: %h", rx_byte_out))
           //$display("[UART] Received Flag High! Data on Bus: %h", rx_byte_out);
        end
    end


		// =========================================================================
    // CLI decoder
    // =========================================================================
    
    cli_decoder cli_decoder_i (
		  .clk(clk), //input  wire        clk,
		  .rst_n(rst_n), //input  wire        rst_n,
		  .rx_byte(rx_byte_out), //input  wire [7:0]  rx_byte,      // From your UART rx_byte_out
		  .rx_done_tick(rx_done_tick), //input  wire        rx_done_tick, // From your UART rx_done_tick
		  .cmd_acquire(cmd_acquire), //output reg         cmd_start,
		  .cmd_read(cmd_read) //output reg         cmd_stop
		);
    
    // Monitor the Output of the decoder
    always @(posedge clk) begin
        if (cmd_acquire) begin
        	`print("UART", $sformatf("Received word 'acquire' from decoder"))
            //$display("[UART] Received word 'acquire' from decoder");
        end
        if (cmd_read) begin
        	`print("UART", $sformatf("Received word 'read' from decoder"))
            //$display("[UART] Received word 'read' from decoder");
        end
    end

endmodule
