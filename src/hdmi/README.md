This is the HDMI module taken from NanoMig/src/hdmi, modified to output vsync/cx/cy/frame_width/frame_height.
For compatibility with yosys it has been automatically converted to verilog using sv2v.
Steps to reproduce:

```
sv2v --write=adjacent *sv
mv serializer.v serializer_gowin.v
sv2v -DLATTICE serializer.sv > serializer_lattice.v > serializer_lattice.v
```
