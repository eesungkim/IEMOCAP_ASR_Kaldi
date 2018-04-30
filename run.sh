#!/bin/bash
# This script builds IEMOCAP ASR model based on kaldi toolkit.
# EESUNGKIM
# eesungk@gmail.com

KALDI_ROOT=/home3/kaldi
kaldi=/home3/kaldi

source=/home3/kaldi/egs/IEMOCAP/IEMOCAP
#source=/home3/kaldi/download/DB/IEMOCAP
logfile=1st_test0306_16
log_dir=log_0306_16
resultfile=result0306_4.txt

train_nj=2
test_nj=2
decode_nj=2

### CMD
train_cmd=utils/run.pl
decode_cmd=utils/run.pl

### Directories.
train_dir=data/train
test_dir=data/test
lang_dir=data/lang
dict_dir=data/local/dict
log_dir=log

################
prepare_data=1
prepare_lm=1
extract_train_mfcc=1
extract_test_mfcc=1
extract_train_plp=0
extract_test_plp=0

# Training
train_mono=1
train_tri1=1
train_tri2=0
train_tri3=0
train_dnn=0

# Decoding
decode_mono=1
decode_tri1=1
decode_tri2=0
decode_tri3=0
decode_dnn=0

# Result
display_result=1

# Options.
# Monophone
mono_train_opt="--boost-silence 1.25 --nj $train_nj --cmd $train_cmd"
mono_align_opt="--nj $train_nj --cmd $decode_cmd"
mono_decode_opt="--nj $decode_nj --cmd $decode_cmd"

# Tri1
tri1_train_opt="--cmd $train_cmd"
tri1_align_opt="--nj $train_nj --cmd $decode_cmd"
tri1_decode_opt="--nj $decode_nj --cmd $decode_cmd"

# Tri2
tri2_train_opt="--cmd $train_cmd"
tri2_align_opt="--nj $train_nj --cmd $decode_cmd"
tri2_decode_opt="--nj $decode_nj --cmd $decode_cmd"

# Tri3
tri3_train_opt="--cmd $train_cmd"
tri3_align_opt="--nj $train_nj --cmd $decode_cmd"
tri3_decode_opt="--nj $decode_nj --cmd $decode_cmd"

# SGMM
sgmm2_train_opt="--cmd $train_cmd"
sgmm2_align_opt="--nj $train_nj --cmd $decode_cmd --transform-dir exp/tri3_ali"
sgmm2_decode_opt="--nj $decode_nj --cmd $decode_cmd --transform-dir exp/tri3_ali"

# SGMM + MMI
sgmm_denlats_opt="--nj $train_nj --sub-split 40 --transform-dir exp/tri3_ali"
sgmmi_train_opt="--cmd $train_cmd --transform-dir exp/tri3_ali"
sgmmi_decode_opt="--transform-dir exp/tri3/decode"

# DNN
dnn_function="train_tanh_fast.sh"
dnn_train_opt=""
dnn_decode_opt="--nj $decode_nj --transform-dir exp/tri3/decode"


# Start logging.
mkdir -p $log_dir
echo ====================================================================== |
echo "                       Kaldi ASR Project	                	  " |
echo ====================================================================== |
echo Tracking the training procedure on: `date` |
echo KALDI_ROOT: $kaldi |
echo DATA_ROOT: $source |
START=`date +%s`

# This step will generate path.sh based on written path above.
./path.sh $kaldi
./local/check_code.sh $kaldi

# Prepare data for training.
if [ $prepare_data -eq 1 ]; then
	echo ====================================================================== |
	echo "                       Data Preparation	                	  " |
	echo ====================================================================== |
	# In each train and test data folder, distribute 'text', 'utt2spk', 'spk2utt', 'wav.scp', 'segments'.
	for set in train test; do
		echo -e "Generating prerequisite files...\nSource directory:$source/$set" |
		local/iemocap_prep_data.sh \
			$source/$set \
			data/$set || exit 1

		utils/validate_data_dir.sh data/$set
		utils/fix_data_dir.sh data/$set
	done
fi

### Language Model
if [ $prepare_lm -eq 1 ]; then
	echo ====================================================================== |
	echo "                       Language Modeling	                	  " |
	echo ====================================================================== | 

	# Generate lexicon, lexiconp, silence, nonsilence, optional_silence, extra_questions
	# from the train dataset.
	echo "Generating dictionary related files..." 
	#local/iemocap_prep_dict.sh $dict_dir 
	local/iemocap_prep_dict1.sh $dict_dir 

	# Make ./data/lang folder and other files.
	echo "Generating language models..." |
	utils/prepare_lang.sh $dict_dir "<UNK>" $lang_dir/local/lang $lang_dir
	utils/prepare_lang.sh data/local/dict "<unk>" data/local/lang data/lang

	# Set ngram-count folder.
	if [[ -z $(find $KALDI_ROOT/tools/srilm/bin -name ngram-count) ]]; then
		echo "SRILM might not be installed on your computer. Please find kaldi/tools/install_srilm.sh and install the package." #&& exit 1
	else
		nc=`find $KALDI_ROOT/tools/srilm/bin -name ngram-count`
		# Make lm.arpa from textraw.
		$nc -text $train_dir/textraw -lm $lang_dir/lm.arpa
	fi

	# Make G.fst from lm.arpa.
	echo "Generating G.fst from lm.arpa..." 
	cat $lang_dir/lm.arpa | $KALDI_ROOT/src/lmbin/arpa2fst --disambig-symbol=#0 --read-symbol-table=$lang_dir/words.txt - $lang_dir/G.fst
	# Check .fst is stochastic or not.
	$KALDI_ROOT/src/fstbin/fstisstochastic $lang_dir/G.fst

fi

if [ $extract_train_mfcc -eq 1 ] || [ $extract_test_mfcc -eq 1 ] || [ $extract_train_plp -eq 1 ] || [ $extract_test_plp -eq 1 ]; then
	echo ====================================================================== |
	echo "                   Acoustic Feature Extraction	             	  " |
	echo ====================================================================== | 
	### MFCC ###
	if [ $extract_train_mfcc -eq 1 ] || [ $extract_test_mfcc -eq 1]; then
		# Generate mfcc configure.
		mkdir -p conf
		#echo -e '--use-energy=false\n--sample-frequency=16000' > conf/mfcc.conf
		# mfcc feature extraction.
		mfccdir=mfcc
	fi
	if [ $extract_train_mfcc -eq 1 ]; then
		echo "Extracting train data MFCC features..."
		steps/make_mfcc.sh \
			--nj $train_nj \
		 	$train_dir \
		 	exp/make_mfcc/train \
		 	$mfccdir
		# Compute cmvn. (This steps should be processed right after mfcc features are extracted.)
		echo "Computing CMVN on train data MFCC..." 
		steps/compute_cmvn_stats.sh \
		 	$train_dir \
		 	exp/make_mfcc/train \
		 	$mfccdir
	fi
	if [ $extract_test_mfcc -eq 1 ]; then
		echo "Extracting test data MFCC features..."
		steps/make_mfcc.sh \
		    --nj $test_nj \
		 	$test_dir \
		 	exp/make_mfcc/test \
		 	$mfccdir
		# Compute cmvn. (This steps should be processed right after mfcc features are extracted.)
		echo "Computing CMVN on test data MFCC..."
		steps/compute_cmvn_stats.sh \
		 	$test_dir \
		 	exp/make_mfcc/test \
		 	$mfccdir
	fi
	# data directories sanity check.
	echo "Examining generated datasets..." 
	utils/validate_data_dir.sh $train_dir
	utils/fix_data_dir.sh $train_dir
fi

if [ $train_mono -eq 1 ] || [ $decode_mono -eq 1 ]; then
	echo ====================================================================== |
	echo "                    Train & Decode: Monophone	              	  " | 
	echo ====================================================================== |
	
	# Monophone train.
	if [ $train_mono -eq 1 ]; then

		echo "Monophone trainig options: $mono_train_opt" 
		echo "Training monophone..."
		steps/train_mono.sh \
			$mono_train_opt \
			$train_dir \
			$lang_dir \
			exp/mono || exit 1
	
		# Monophone aglinment.
		# train된 model파일인 mdl과 occs로부터 새로운 align을 생성
		echo "Monophone aligning options: $mono_align_opt" 
		echo "Aligning..." 
		steps/align_si.sh \
			$mono_align_opt \
			$train_dir \
			$lang_dir \
			exp/mono \
			exp/mono_ali || exit 1
	fi

	# Graph structuring.
	# make HCLG graph
	# This script creates a fully expanded decoding graph (HCLG) that represents
	# all the language-model, pronunciation dictionary (lexicon), context-dependency,
	# and HMM structure in our model.  The output is a Finite State Transducer
	# that has word-ids on the output, and pdf-ids on the input (these are indexes
	# that resolve to Gaussian Mixture Models).
	# will be made a graph in exp/mono/graph
	if [ $decode_mono -eq 1 ]; then
		
		echo "Generating monophone graph..."  
		utils/mkgraph.sh \
		$lang_dir \
		exp/mono \
		exp/mono/graph 

		# Data decoding.
		echo "Monophone decoding options: $mono_decode_opt" 
		echo "Decoding with monophone model..."  
		steps/decode.sh \
			$mono_decode_opt \
			exp/mono/graph \
			$test_dir \
			exp/mono/decode
	fi

	### Optional ###
	# tree structuring.
	# $KALDI_ROOT/src/bin/draw-tree $lang_dir/phones.txt exp/mono/tree \
	# | dot -Tps -Gsize=8,10.5 | ps2pdf - tree.pdf 2>/dev/null
fi

if [ $train_tri1 -eq 1 ] || [ $decode_tri1 -eq 1 ]; then
	echo ====================================================================== |  
	echo "           Train & Decode: Triphone1 [delta+delta-delta]	       	  " | 
	echo ====================================================================== |  

	# Triphone1 training.
	if [ $train_tri1 -eq 1 ]; then

		echo "Triphone1 training options: $tri1_train_opt"	
		echo "Training delta+double-delta..." 
		steps/train_deltas.sh \
			$tri1_train_opt \
			2000 \
			10000 \
			$train_dir \
			$lang_dir \
			exp/mono_ali \
			exp/tri1 || exit 1

		# Triphone1 aglining.
		echo "Triphone1 aligning options: $tri1_align_opt"	
		echo "Aligning..." 
		steps/align_si.sh \
			$tri1_align_opt \
			$train_dir \
			$lang_dir \
			exp/tri1 \
			exp/tri1_ali ||  exit 1
	fi

	if [ $decode_tri1 -eq 1 ]; then
		# Graph drawing.
		echo "Generating delta+double-delta graph..." 
		utils/mkgraph.sh \
			$lang_dir \
			exp/tri1 \
			exp/tri1/graph

		# Data decoding.
		echo "Triphone1 decoding options: $tri1_decode_opt"	
		echo "Decoding with delta+double-delta model..."  
		steps/decode.sh \
			$tri1_decode_opt \
			exp/tri1/graph \
			$test_dir \
			exp/tri1/decode
	fi
fi

if [ $train_tri2 -eq 1 ] || [ $decode_tri2 -eq 1 ]; then
	echo ======================================================================  
	echo "               Train & Decode: Triphone2 [LDA+MLLT]	       	  " 
	echo ====================================================================== 
	start6=`date +%s`; log_s6=`date | awk '{print $4}'`
	echo $log_s6 >> $log_dir/$logfile.log 
	echo START TIME: $log_s6 | tee -a $log_dir/$logfile.log 


	# Triphone2 training.
	if [ $train_tri2 -eq 1 ]; then
		echo "Triphone2 trainig options: $tri2_train_opt"	
		echo "Training LDA+MLLT..."
		steps/train_lda_mllt.sh \
			$tri2_train_opt \
			2500 \
			15000 \
			$train_dir \
			$lang_dir \
			exp/tri1_ali \
			exp/tri2 ||  exit 1

		# Triphone2 aglining.
		echo "Triphone2 aligning options: $tri2_align_opt"
		echo "Aligning..." 
		steps/align_si.sh \
			$tri2_align_opt \
			$train_dir \
			$lang_dir \
			exp/tri2 \
			exp/tri2_ali ||  exit 1
	fi

	if [ $decode_tri2 -eq 1 ]; then
		# Graph drawing.
		echo "Generating LDA+MLLT graph..." 
		utils/mkgraph.sh \
			$lang_dir \
			exp/tri2 \
			exp/tri2/graph

		# Data decoding.
		echo "Triphone2 decoding options: $tri2_decode_opt"	
		echo "Decoding with LDA+MLLT model..."
		steps/decode.sh \
			$tri2_decode_opt \
			exp/tri2/graph \
			$test_dir \
			exp/tri2/decode
	fi

	end6=`date +%s`; log_e6=`date | awk '{print $4}'`
	taken6=`local/track_time.sh $start6 $end6`
	echo END TIME: $log_e6  
	echo PROCESS TIME: $taken6 sec 
fi

if [ $train_tri3 -eq 1 ] || [ $decode_tri3 -eq 1 ]; then
	echo ======================================================================  
	echo "             Train & Decode: Triphone3 [LDA+MLLT+SAT]	       	  " 
	echo ====================================================================== 
	start7=`date +%s`; log_s7=`date | awk '{print $4}'`
	echo $log_s7 
	echo START TIME: $log_s7 


	# Triphone3 training.
	if [ $train_tri3 -eq 1 ]; then
		echo "Triphone3 trainig options: $tri3_train_opt"
		echo "Training LDA+MLLT+SAT..." 
		steps/train_sat.sh \
			$tri3_train_opt \
			2500 \
			15000 \
			$train_dir \
			$lang_dir \
			exp/tri2_ali \
			exp/tri3 ||  exit 1

		# Triphone3 aglining.
		echo "Triphone3 aligning options: $tri3_align_opt" 
		echo "Aligning..." 
		steps/align_fmllr.sh \
			$tri3_align_opt \
			$train_dir \
			$lang_dir \
			exp/tri3 \
			exp/tri3_ali ||  exit 1
	fi

	if [ $decode_tri3 -eq 1 ]; then
		# Graph drawing.
		echo "Generating LDA+MLLT+SAT graph..."
		utils/mkgraph.sh \
			$lang_dir \
			exp/tri3 \
			exp/tri3/graph

		# Data decoding: train and test datasets.
		echo "Tirphone3 decoding options: $tri3_decode_opt" 
		echo "Decoding with LDA+MLLT+SAT model..."
		steps/decode_fmllr.sh \
			$tri3_decode_opt \
			exp/tri3/graph \
			$test_dir \
			exp/tri3/decode
	fi

	end7=`date +%s`; log_e7=`date | awk '{print $4}'`
	taken7=`local/track_time.sh $start7 $end7`
	echo END TIME: $log_e7  
	echo PROCESS TIME: $taken7 sec 
fi

### DNN training
if [ $train_dnn -eq 1 ] || [ $decode_dnn -eq 1 ]; then
	echo ====================================================================== 
	echo "                       Train & Decode: DNN  	                 "  
	echo ====================================================================== 
	start10=`date +%s`; log_s10=`date | awk '{print $4}'`
	echo $log_s10 >> $log_dir/$logfile.log 
	echo START TIME: $log_s10 | tee -a $log_dir/$logfile.log 

	# DNN training.
	if [ $train_dnn -eq 1 ]; then
		# train_tanh_fast.sh
		echo "DNN($dnn_function) trainig options: $dnn_train_opt"				
		echo "Training DNN..." 
		steps/nnet2/$dnn_function \
			$dnn_train_opt \
			$train_dir \
			$lang_dir \
			exp/tri3_ali \
			exp/tri4 ||  exit 1
	fi

	# DNN decoding.
	if [ $decode_dnn -eq 1 ]; then
		# Data decoding: train dataset.
		echo "DNN($dnn_function) decoding options: $dnn_decode_opt"	
		echo "Decoding with DNN model..." 
		steps/nnet2/decode.sh \
			$dnn_decode_opt \
			exp/tri3/graph \
			$test_dir \
			exp/tri4/decode
	fi

	end10=`date +%s`; log_e10=`date | awk '{print $4}'`
	taken10=`local/track_time.sh $start10 $end10`
	echo END TIME: $log_e10  
	echo PROCESS TIME: $taken10 sec 


fi

if [ $display_result -eq 1 ]; then 
	echo ====================================================================== | tee -a $log_dir/$logfile.log 
	echo "                             RESULTS  	                	      " | tee -a $log_dir/$logfile.log 
	echo ====================================================================== | tee -a $log_dir/$logfile.log 
	echo "Displaying results" | tee -a $log_dir/$logfile.log

	# Save result in the log folder.
	echo "Displaying results" | tee -a $log_dir/$logfile.log
	local/make_result.sh exp log $resultfile
	echo "Reporting results..." | tee -a $log_dir/$logfile.log
	cat log/$resultfile | tee -a $log_dir/$logfile.log
fi

##########################################################
# for final log.
echo "Training procedure finished successfully..." | tee -a $log_dir/$logfile.log
END=`date +%s`
taken=`local/track_time.sh $START $END`
echo TOTAL TIME: $taken sec  | tee -a $log_dir/$logfile.log 

