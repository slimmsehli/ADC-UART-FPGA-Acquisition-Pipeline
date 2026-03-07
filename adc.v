
// ADC : 60MHz 

module adc (
    input  wire        enable,
    output wire  [9:0]  adc_data
);
    parameter CLK_PERIOD = 17; // 60MHz = 16ps period
    reg clk    = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

		reg  [9:0] temp_data;
    always @(posedge clk) begin
        if (enable) begin
          temp_data <= temp_data+1;
        end 
        else 
        	temp_data <= 0;
    end
    assign adc_data = temp_data;
endmodule
