transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

asim +access +r +m+ila_0  -L xil_defaultlib -L secureip -O5 xil_defaultlib.ila_0

do {ila_0.udo}

run 1000ns

endsim

quit -force
