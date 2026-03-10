module top;
    
    // clocks parameters 
    parameter CLK100_FREQUENCY = 100_000_000; // (MHz) FPGA clock : 100MHz
    parameter CLK100_PERIOD = 10 ; // 10ps
    parameter CLK60_FREQUENCY = 60_000_000; 
    parameter CLK60_PERIOD = 16.66 ; 
    
    // parametrs and signals ofr the UART
    parameter BAUD_RATE  = 9600; //19200, 115200;
    parameter CPB  = CLK100_FREQUENCY / BAUD_RATE ; //868;   // 100MHz / 115200
    parameter BIT_PERIOD  = CPB * CLK100_PERIOD;
    parameter UART_HALF = CPB/2; //434;
    parameter UART_FULL = CPB; //868;
    // ADC
    parameter adc_values_packet = 10; // the number of values to be sampled from the ADC
    // FIFO
    parameter DATA_WIDTH = 10;
    parameter ADDR_WIDTH = adc_values_packet; // the length of the FIFO since the read is fatsre than the write it is okay to have it smaller than the samples count
    
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
    reg  [DATA_WIDTH-1:0] adc_data;
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
    // a simple synchronizer for the reset signal on both sides of the fifo
    // ========================================================================= 
    reg [1:0] reset_60_sync;
		
		always @(posedge clk_60 or negedge reset) begin
			if (!reset) reset_60_sync <= 2'b00;
			else 				reset_60_sync <= {reset_60_sync[0], 1'b1};
		end
		wire reset_60_synced = reset_60_sync[1];
		
		reg [1:0] reset_100_sync;
		always @(posedge clk_100 or negedge reset) begin
			if (!reset) reset_100_sync <= 2'b00;
			else 				reset_100_sync <= {reset_100_sync[0], 1'b1};
		end
		wire reset_100_synced = reset_100_sync[1];
		
		// =========================================================================
    // FIFO : 
    // =========================================================================
    
		wire fifo_full;
		wire fifo_empty;
		reg w_en;
		reg r_en;
		reg [DATA_WIDTH-1:0] wdata;
		reg [DATA_WIDTH-1:0] rdata;
		
		async_fifo #(
		  .DATA_WIDTH(DATA_WIDTH), //parameter DATA_WIDTH = 10,
		  .ADDR_WIDTH(ADDR_WIDTH) //parameter ADDR_WIDTH = 4 // 2^4 = 16 locations
		)
			fifo
		(
				// Write Domain (60MHz)
				.wclk(clk_60), //input  wire                   wclk,
				.wrst_n(reset_60_synced), //input  wire                   wrst_n,
				.w_en(w_en), //input  wire                   w_en,
				.wdata(wdata), //input  wire [DATA_WIDTH-1:0]  wdata,
				.full(fifo_full), //output wire                   full,

				// Read Domain (100MHz)
				.rclk(clk_100), //input  wire                   rclk,
				.rrst_n(reset_100_synced), //input  wire                   rrst_n,
				.r_en(r_en), //input  wire                   r_en,
				.rdata(rdata), //output wire [DATA_WIDTH-1:0]  rdata,
				.empty(fifo_empty) //output wire                   empty
		);
		
		// =========================================================================
    // a simple synchronizer for the aquire signal to cross clock domains 100MHz to 60 MHz
    // ========================================================================= 
		reg sync1;
		reg cmd_acquire_sync60;
		always @(posedge clk_60) begin
			sync1 <= cmd_acquire;
			cmd_acquire_sync60 <= sync1;
		end
		
		// =========================================================================
    // Memory Management for data from ADC to memory : 60 mhz
    // ========================================================================= 
		
		reg [2:0] mem_status_60;
		reg [15:0] fifo_counter_60;
		
		typedef enum {IDLE= 3'b000, READ= 3'b001, CONVERT= 3'b010, WRITE= 3'b011} status;
		
		always @(posedge clk_60 or negedge reset_60_synced) begin
			if (!reset_60_synced) begin
				enable_adc <= 0;
				mem_status_60 <= IDLE;
				fifo_counter_60 <= 0;
			end
				else begin
				case (mem_status_60)
					IDLE: begin // nothing just sit there waiting for the aquire signal
						fifo_counter_60 <= 0;
						wdata <= 0;
						w_en <= 0;
						if (cmd_acquire_sync60) begin
							// need to implment a waiting state until the adc wakes up (to be dfined by the ADC)
							enable_adc <= 1; 
							mem_status_60 <= READ;
						end
					end 
					READ: begin
						if (!fifo_full) begin
							wdata <= adc_data;
							w_en <= 1;
							fifo_counter_60 <= fifo_counter_60 + 1;
							if (fifo_counter_60 == adc_values_packet-1) begin
								mem_status_60 <= IDLE;
								enable_adc <= 0; //disable the adc after 10k values captured
								w_en <= 0; // disbale the fifo write 
								wdata <= 0;
							end
						end
						else begin
							w_en <= 0; // disbale the fifo write 
						end
					end
					default: mem_status_60 <= IDLE;
				endcase
			end
		end
		
		// =========================================================================
    // Memory Management for data from fifo to the hyper memory : 100 mhz
    // ========================================================================= 
		reg [15:0] hypermem_fifo [adc_values_packet];
		reg [2:0] mem_status_100;
		reg [15:0] fifo_counter_100;
		reg        reading_active;
		
    always @(posedge clk_100 or negedge reset_100_synced) begin
			if (!reset_100_synced) begin
				r_en <= 0;
        fifo_counter_100 <= 0;
        reading_active <= 0;
			end
				else begin
					r_en <= 0;
					if (!fifo_empty && !reading_active) begin
						r_en <= 1;
						reading_active <= 1;
					end
					
					if (reading_active) begin
						hypermem_fifo[fifo_counter_100] <= rdata;
						fifo_counter_100 <= fifo_counter_100 + 1;
						reading_active <= 0;
					end	
			end
		end
		final begin
			$writememh("memory_hyperout.hex", hypermem_fifo); // this is for checking hte adc out compared to the data saved to the memory 
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
