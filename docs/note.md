

Verilog Model for the HyperRAM from IFX - S80KS5122-HYPERBUS
https://www.infineon.com/gated/infineon-verilog-model-for-hyperbus-interface-simulationmodels-en_bbc7fc83-6f5a-4731-bf16-e31ebffc63e0

model instanciation :
s80ks5122 DUT (
.DQ7(DQ[7]) ,
.DQ6(DQ[6]) ,
.DQ5(DQ[5]) ,
.DQ4(DQ[4]) ,
.DQ3(DQ[3]) ,
.DQ2(DQ[2]) ,
.DQ1(DQ[1]) ,
.DQ0(DQ[0]) ,
.RWDS(RWDS) ,
.CSNeg(CS) ,
.CK(CK) ,
.CKn() ,
.RESETNeg(dut_reset)
 )
