vlib work
vlog -sv {../../01_FPGA/src/project/required_preprocess1065_20261028/histogram_lane1076.v} {../../01_FPGA/src/project/required_preprocess1065_20261028/gray_histeq1065.v} {../../01_FPGA/src/project/required_preprocess1065_20261028/gaussian_gray1069.v} {../../01_FPGA/src/project/required_preprocess1065_20261028/required_preprocess1070.v} {tb_required1070.sv}
vsim -c work.tb_required1070
run -all
quit -f
