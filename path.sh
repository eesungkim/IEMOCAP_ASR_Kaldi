
export KALDI_ROOT=/home3/kaldi
[ -f $KALDI_ROOT/tools/env.sh ] && . $KALDI_ROOT/tools/env.sh
export PATH=$PWD/utils/:$KALDI_ROOT/tools/openfst/bin:$KALDI_ROOT/tools/irstlm/bin/:$PWD:$PATH
[ ! -f $KALDI_ROOT/tools/config/common_path.sh ] && echo >&2 "The standard file $KALDI_ROOT/tools/config/common_path.sh is not present -> Exit!" && exit 1
. $KALDI_ROOT/tools/config/common_path.sh
export LC_ALL=C

root=$1
valgrind=no

if [ $valgrind == "no" ]; then
  export PATH=${root}/src/bin:${root}/tools/openfst/bin:${root}/src/fstbin/:${root}/src/gmmbin/:${root}/src/featbin/:${root}/src/fgmmbin:${root}/src/sgmmbin:${root}/src/lm:${root}/src/latbin:$PATH  
else 
  mkdir bin
  for x in ${root}/src/{bin,fstbin,gmmbin,featbin,fgmmbin,sgmmbin,lm,latbin}; do
    for y in $x/*; do
      if [ -x $y ]; then
        b=`basename $y`
        echo valgrind $y '"$@"' > bin/$b
        chmod +x bin/`basename $b`
      fi
    done
  done
  export PATH=`pwd`/bin/:${root}/tools/openfst/bin:$PATH
fi
export PATH=$PATH:$PWD/utils:$PWD/steps:$root/src/nnet2bin:$root/src/sgmm2bin

