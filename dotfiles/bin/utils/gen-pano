#!/bin/sh
pto_gen -o project.pto *.jpg
cpfind -o project.pto --multirow --celeste project.pto
cpclean -o project.pto project.pto
linefind -o project.pto project.pto
autooptimiser -a -m -l -s -o project.pto project.pto
pano_modify --center --straighten --ldr-file=JPG  --canvas=AUTO --crop=AUTO -o project.pto project.pto
hugin_executor --stitching --prefix=pano-$(date +%Y-%m-%d) project.pto
# rm project.pto
