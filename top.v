module top;
		parameter CLK_PERIOD = 10;
    parameter MAX_CYCLES = 500_000_000;
    parameter GPIO_COUNT = 16;
    parameter MEM_WORDS  = 32768;
    parameter VERBOSE    = 0;
    
    // Bit periods at 115200 baud / 100 MHz clock
    localparam UART_HALF = 434;
    localparam UART_FULL = 868;
    
    // clocks 
    parameter CLK100_FREQUENCY = 100_000_000; // (MHz) FPGA clock : 100MHz
    parameter CLK100_PERIOD = 10 ; // 10ps
    parameter CLK60_FREQUENCY = 60_000_000; 
    parameter CLK60_PERIOD = 16.66 ; 
    
    // parametrs and signals ofr the UART
    parameter BAUD_RATE  = 9600; //19200, 115200;
    parameter CPB  = CLK100_FREQUENCY / BAUD_RATE ; //868;   // 100MHz / 115200
    parameter BIT_PERIOD  = CPB * CLK100_PERIOD;
    
    
    
    
    // clocks
    reg clk_100    = 0;
    always #(CLK100_PERIOD/2) clk_100 <= ~clk_100;
    reg clk_60    = 0;
    always #(CLK60_PERIOD/2) clk_60 <= ~clk_60;
    
    // others signals
    reg reset;
    reg [15:0] baudrate;
    reg uart_rx;
    reg  [7:0]  rx_byte_out;
    wire rx_done_tick;
    wire         cmd_acquire;
    wire         cmd_read;    
    reg [7:0] command_list [0:3];
    integer i;
    
    // =========================================================================
    // ADC : a dummy ADC that generates a  signal at 10 bits at 60MHz 
    // =========================================================================
    parameter CLK_PERIOD_adc = 17; // 60MHz = 16ps period
    reg clk_adc    = 0;
    always #(CLK_PERIOD_adc/2) clk_adc = ~clk_adc;
    reg  [9:0] adc_data;
    reg enable_adc;
    
    adc adc_i (
		  .enable(enable_adc),
		  .adc_data(adc_data) //reg  [9:0] 
    );
    
    // =========================================================================
    // UART with decoder
    // =========================================================================

    uart_decoder_top uart_decoder_top_i (
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
			//.tx_byte_in(tx_byte_in), //input  wire [7:0]  tx_byte_in,
			//.(tx_start) //input  wire        tx_start
			// decoder output
		  .cmd_acquire(cmd_acquire), //output reg         cmd_start,
		  .cmd_read(cmd_read) //output reg         cmd_stop
		);
		
		// =========================================================================
    // FIFO
    // =========================================================================
    parameter DATA_WIDTH = 10;
    parameter ADDR_WIDTH = 100;
		wire fifo_full;
		reg w_en;
		reg [DATA_WIDTH-1:0] wdata;
		async_fifo #(
		  .DATA_WIDTH(DATA_WIDTH), //parameter DATA_WIDTH = 10,
		  .ADDR_WIDTH(ADDR_WIDTH) //parameter ADDR_WIDTH = 4 // 2^4 = 16 locations
		)
			fifo
		(
				// Write Domain (60MHz)
				.wclk(clk_60), //input  wire                   wclk,
				.wrst_n(reset), //input  wire                   wrst_n,
				.w_en(w_en), //input  wire                   w_en,
				.wdata(wdata), //input  wire [DATA_WIDTH-1:0]  wdata,
				.full(fifo_full), //output wire                   full,

				// Read Domain (100MHz)
				.rclk(), //input  wire                   rclk,
				.rrst_n(), //input  wire                   rrst_n,
				.r_en(), //input  wire                   r_en,
				.rdata(), //output wire [DATA_WIDTH-1:0]  rdata,
				.empty() //output wire                   empty
		);
		
		// =========================================================================
    // Memory Management for data 
    // =========================================================================
		// logic part to enable the capture of 10000 value and put them into memory 
		// memory to hold the 10k values at 10 bits 
		parameter adc_values_packet = 10000;
		reg [15:0] hypermem_fifo [adc_values_packet];
		reg [2:0] mem_status;
		reg [15:0] hypermem_fifo_counter;
		
		typedef enum {IDLE= 3'b000, READ= 3'b001, CONVERT= 3'b010, WRITE= 3'b011} status;
		
		always @(posedge clk_60 or negedge reset) begin
			if (!reset) begin
				enable_adc<=0;
				mem_status <= IDLE;
				hypermem_fifo_counter <= 0;
			end
				else begin
				case (mem_status)
					IDLE: begin // nothing just sit there waiting for the aquire signal
						hypermem_fifo_counter <= 0;
						wdata <= 0;
						w_en <= 0;
						if (cmd_acquire) begin
							// need to implment a waiting state until the adc wakes up
							enable_adc <= 1; 
							mem_status <= READ;
						end
					end 
					READ: begin
						wdata <= adc_data;
						w_en <= 1;
						hypermem_fifo_counter <= hypermem_fifo_counter + 1;
						if (hypermem_fifo_counter>adc_values_packet) begin
							mem_status <= IDLE;
							enable_adc <= 0; //disable the adc after 10k values captured
							w_en <= 0; // disbale the fifo write 
							wdata <= 0;
						end
					end
					default: mem_status <= IDLE;
				endcase
			end
		end
		
    
    
    // =========================================================================
    // TB
    // =========================================================================
    
    // UART TX task 
    task send_uart_byte(input [7:0] data);
        integer bit_idx;
        begin
            // Start Bit (Low)
            uart_rx = 0;
            #(BIT_PERIOD);
            
            // Data Bits (LSB first)
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                uart_rx = data[bit_idx];
                #(BIT_PERIOD);
            end
            
            // Stop Bit (High)
            uart_rx = 1;
            #(BIT_PERIOD);
            `print("TB", $sformatf("Sent Byte: %h ('%c') ", data, data))
        end
    endtask
    
    initial begin
		  $display("=================================================");
		  $display("[TB]   ADC AQUISITION  ");
		  $display("[TB]   FPGA CLOCK : 100MHz  ");
		  $display("[TB]   ADC CLOCK : 60MHz  ");
		  $display("[TB]   UART BAUDRATE : %d  ", BAUD_RATE);
		  $display("=================================================");
		  reset = 0;
		  uart_rx = 1;
		  baudrate = CPB;
		  // Populate Command List
		  command_list[0] = 8'h61; // 'a' (Acquire)
		  command_list[1] = 8'h72; // 'r' (Read)
		  command_list[2] = 8'h73; // 's' (Status)
		  command_list[3] = 8'h74; // 't' (Test)
		  
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

		  #(BIT_PERIOD * 10);
		  $display("=================================================");
		  $display("[TB] Simulation Finished");
		  $display("=================================================");
		  $finish;
    end
    
    
    
    
    
    
    
    
    
    
    
    
    
		
		
		// =========================================================================
    // UART TX monitor — decodes serial from the real TX pad
    // =========================================================================
    reg uart_pad_tx; // uart rx pin
    integer uart_state = 0;
    integer uart_cnt   = 0;
    integer uart_bit   = 0;
    reg [7:0] uart_byte = 0;

    always @(posedge clk) begin
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

		string vcd_file;
		initial begin
        //if (!$value$plusargs("MEM_FILE=%s", mem_file_padded))
        //    mem_file_padded = "firmware.hex";
        if (!$value$plusargs("VCD_FILE=%s", vcd_file))
            vcd_file = "waves.vcd";
        //mem_file = mem_file_padded[255:0];
        //vcd_file = vcd_file_padded[255:0];
    end
    
    // =========================================================================
    // Clock & Reset
    // =========================================================================
    reg clk    = 0;
    reg resetn = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    initial begin repeat(8) @(posedge clk); resetn = 1; end
    //initial begin repeat(100) @(posedge clk); $finish; end
    
    // =========================================================================
    // VCD
    // =========================================================================
    initial begin
        #1;
        $dumpfile(vcd_file);
        $dumpvars(0, top);
    end

endmodule
