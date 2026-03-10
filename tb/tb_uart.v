
/* verilator lint_off WIDTHTRUNC */
/* verilator lint_off UNUSEDPARAM */
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off UNDRIVEN */

module tb_uart;
    
    // clocks parameters 
    parameter CLK100_FREQUENCY = 100_000_000; // (MHz) FPGA clock : 100MHz
    parameter CLK100_PERIOD = (1.0E9/CLK100_FREQUENCY) ; // 10ps
    
    // parametrs and signals ofr the UART
    parameter BAUD_RATE  = 9600; //19200, 115200;
    parameter baudrate_tickes  = CLK100_FREQUENCY / BAUD_RATE ; //868;   // 100MHz / 115200
    parameter BIT_PERIOD  = baudrate_tickes * CLK100_PERIOD;
    parameter UART_HALF = baudrate_tickes/2; //434;
    parameter UART_FULL = baudrate_tickes; //868;
    // ADC
    parameter adc_values_packet = 10; // the number of values to be sampled from the ADC
    // FIFO
    //parameter DATA_WIDTH = 10;
    //parameter ADDR_WIDTH = adc_values_packet; // the length of the FIFO since the read is fatsre than the write it is okay to have it smaller than the samples count
    
    // clocks
    reg clk_100    = 0;
    always #(CLK100_PERIOD/2) clk_100 <= ~clk_100;
    
    // others signals
    reg uart_rx_t;
    reg reset;
    reg [15:0] baudrate = baudrate_tickes;
    reg uart_rx;
    wire uart_tx;
    reg  [7:0]  rx_byte_out, tx_byte_in;
    wire rx_done_tick, tx_busy;
    reg tx_start; 
    reg [7:0] command_list [0:3];
    
    // =========================================================================
    // UART with decoder
    // =========================================================================

    uart uart_i (
	.clk(clk_100), //input  wire        clk,
	.rst_n(reset), //input  wire        rst_n,
	// Configuration Registers
	.clks_per_bit(baudrate), //input  wire [15:0] clks_per_bit(baudrate),
	// Physical Lines
	.uart_rx(uart_rx),
	.uart_tx(uart_tx),
	// Internal Interface
	.rx_byte_out(rx_byte_out), //output reg  [7:0]  rx_byte_out,
	.rx_done_tick(rx_done_tick), //output reg         rx_done_tick,
	.tx_byte_in(tx_byte_in), //input  wire [7:0]  tx_byte_in,
	.tx_start(tx_start), //input  wire        tx_start
	.tx_busy(tx_busy)
	);
    
    // uart send process
    task uart_send(input [7:0] data);
        begin
            @(posedge clk_100);
            tx_byte_in = data;
            tx_start = 1'b1;
            @(posedge clk_100);
            tx_start = 1'b0;
            @(negedge tx_busy);
        end
    endtask
    
    // uart receive process
    task uart_get(output [7:0] data_out);
        begin
            @(posedge rx_done_tick);
            data_out = rx_byte_out;
        end
    endtask
    
    	
    // =========================================================================
    // TX function to test the uart module
    // =========================================================================
    // UART TX task 
    task send_uart_byte(input [7:0] data);
        integer bit_idx;
        begin
            // Start Bit (Low)
            uart_rx_t = 0;
            #(BIT_PERIOD);
            
            // Data Bits (LSB first)
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                uart_rx_t = data[bit_idx];
                #(BIT_PERIOD);
            end
            
            // Stop Bit (High)
            uart_rx_t = 1;
            #(BIT_PERIOD);
            `print("TB", $sformatf("Sent Byte: %h ('%c') ", data, data))
        end
    endtask
    
    // =========================================================================
    // UART TX monitor 
    // =========================================================================
    reg uart_pad_tx; // uart rx pin
    integer uart_state = 0;
    integer uart_cnt   = 0;
    integer uart_bit   = 0;
    reg [7:0] uart_byte = 0;

    always @(posedge clk_100) begin
        case (uart_state)
            0: if (uart_pad_tx == 1'b0) begin
                uart_state <= 1;
                uart_cnt   <= UART_HALF;
            end
            1: if (uart_cnt == 0) begin
                uart_state <= 2;
                uart_cnt   <= UART_FULL;
                uart_bit   <= 0;
            end else uart_cnt <= uart_cnt - 1;
            2: if (uart_cnt == 0) begin
                uart_cnt <= UART_FULL;
                if (uart_bit < 8) begin
                    uart_byte <= {uart_pad_tx, uart_byte[7:1]};
                    uart_bit  <= uart_bit + 1;
                end else begin
                    $write("%c", uart_byte);
                    uart_state <= 0;
                end
            end else uart_cnt <= uart_cnt - 1;
        endcase
    end
    
    // enable a loopback test where the uart will write to its own rx and read it back 
    reg loopback;
    assign uart_rx = (loopback) ? uart_tx : uart_rx_t;
    
    initial begin
	  $display("=================================================");
	  $display("[TB]   ADC AQUISITION  ");
	  $display("[TB]   FPGA CLOCK : 100MHz  ");
	  $display("[TB]   UART BAUDRATE : %d  ", BAUD_RATE);
	  $display("=================================================");
	  $display("[TB]   TEST1 : Receive  ");
	  reset = 0;
	  uart_rx_t = 1;
	  loopback = 0;
	  // Reset the System
	  #(CLK100_PERIOD * 10);
	  reset = 1;
	  #(CLK100_PERIOD * 10);
	  
	  // --- Test "acquire" ---
	  send_uart_byte(8'h61); // a
	  send_uart_byte(8'h63); // c
	  send_uart_byte(8'h71); // q
	  send_uart_byte(8'h75); // u
	  send_uart_byte(8'h69); // i
	  send_uart_byte(8'h72); // r
	  send_uart_byte(8'h65); // e
	  send_uart_byte(8'h20); // SPACE (Triggers the command)
	  
	  #(BIT_PERIOD * 20); // Wait for processing

	  // --- Test "read" ---
	  send_uart_byte(8'h72); // r
	  send_uart_byte(8'h65); // e
	  send_uart_byte(8'h61); // a
	  send_uart_byte(8'h64); // d
	  send_uart_byte(8'h20); // SPACE
	  
	  #(BIT_PERIOD * 20);
	  $display("=================================================");
	  $display("[TB]   TEST2 : Loopback  ");
	  loopback = 1;
	  for (integer i = 0; i<20; i++ ) begin
	  	uart_send(i); // r
	  end
	  
	  $display("=================================================");
	  $display("[TB]   TEST3 : Parallel Send Receive  ");
	  loopback = 0;
	  #(BIT_PERIOD);
	  fork 
		  begin
		  	#(BIT_PERIOD);
			  for (integer i = 40; i<60; i++ ) begin
			  	uart_send(i); // r
			  end
		  end
  		  begin
			  for (integer i = 0; i<20; i++ ) begin
			  	send_uart_byte(i); // r
			  end
		  end
	  join
	  
	  #(BIT_PERIOD * 20);
	  $display("=================================================");
	  $display("[TB] Simulation Finished");
	  $display("=================================================");
	  $finish;
    end
    
    

    // =========================================================================
    // VCD
    // =========================================================================
    string vcd_file;
    initial begin
        #1;
      	if (!$value$plusargs("VCD_FILE=%s", vcd_file))
            vcd_file = "waves.vcd";
        $dumpfile(vcd_file);
        $dumpvars(0, top);
    end

endmodule
