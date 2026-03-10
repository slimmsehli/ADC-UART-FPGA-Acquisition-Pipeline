
// ADC : 60MHz 

module adc #(
		parameter CLK_PERIOD = 17 // 60MHz = 16ps period
)(
    input  wire        enable,
    output wire  [9:0]  adc_data
);
    reg [10:0] temp_memory [100];
    reg [15:0] tem_memory_counter;
    
    reg clk    = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

		reg  [9:0] temp_data;
    always @(posedge clk) begin
        if (enable) begin
          temp_memory[tem_memory_counter] <= temp_data;
          tem_memory_counter <= tem_memory_counter + 1;
          temp_data <= temp_data + 1;
        end 
        else begin 
        	temp_data <= 0;
        	tem_memory_counter <= 0;
        end
    end
    assign adc_data = temp_data;
    
    // Monitor the Output
    always @(posedge enable) `print("ADC", $sformatf("ADC Enabled"))
    always @(negedge enable) `print("ADC", $sformatf("ADC Disabled"))
    
    final begin
    	$writememh("memory_adc.hex", temp_memory); 
    end
    
endmodule
