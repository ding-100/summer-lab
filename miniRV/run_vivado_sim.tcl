open_project /home/user/summer-lab/miniRV_basic/miniRV.xpr
set_property top soc_simple_tb [get_filesets sim_1]
launch_simulation
run all
close_sim
close_project
exit
