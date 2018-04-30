#!/bin/bash

# Copyright 2010-2012 Microsoft Corporation  
#           2012-2014 Johns Hopkins University (Author: Daniel Povey)
#                2015 Guoguo Chen
#		 2018 modified by Euisung Kim

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
# WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
# MERCHANTABLITY OR NON-INFRINGEMENT.
# See the Apache 2 License for the specific language governing permissions and
# limitations under the License.

# Call this script from one level above, e.g. from the s3/ directory.  It puts
# its output in data/local/.

# The parts of the output of this that will be needed are
# [in data/local/dict/ ]
# lexicon.txt
# extra_questions.txt
# nonsilence_phones.txt
# optional_silence.txt
# silence_phones.txt


echo "$0 $@"  # Print the command line for logging
. utils/parse_options.sh || exit 1;



if [ $# -ne 1 ]; then
   echo "Two arguments should be assigned." 
   echo "#. Source data."
   echo "1. The folder in which generated files are saved." && exit 1
fi

# train data directory.
#data=$1
# savining directory.
save=$1

echo ======================================================================
echo "                              NOTICE                                "
echo ""
echo -e "iemocap_prep_dict: Generate lexicon, lexiconp, silence, nonsilence, \n\toptional_silence, and extra_questions."
echo "CURRENT SHELL: $0"
echo -e "INPUT ARGUMENTS:\n$@"

for check in lexicon.txt lexiconp.txt silence.txt nonsilence.txt optional_silence.txt extra_questions.txt; do
	if [ -f $save/$check ] && [ ! -z $save/$check ]; then
		echo -e "$check is already present but it will be overwritten."
	fi
done
echo ""
echo ======================================================================

# lexicon.txt and lexiconp.txt
if [ ! -d $save ]; then
	mkdir -p $save
fi



# (1) Get the CMU dictionary
svn co  https://svn.code.sf.net/p/cmusphinx/code/trunk/cmudict $save/cmudict || exit 1;
echo "Getting CMU dictionary"
# can add -r 10966 for strict compatibility.


#(2) Dictionary preparation:


# silence phones, one per line. 
for w in sil laughter noise oov; do echo $w; done > $save/silence_phones.txt
echo sil > $save/optional_silence.txt

# For this setup we're discarding stress.
cat $save/cmudict/cmudict.0.7a.symbols | sed s/[0-9]//g | \
  perl -ane 's:\r::; print;' | sort | uniq > $save/nonsilence_phones.txt

# An extra question will be added by including the silence phones in one class.
cat $save/silence_phones.txt| awk '{printf("%s ", $1);} END{printf "\n";}' > $save/extra_questions.txt || exit 1;

grep -v ';;;' $save/cmudict/cmudict.0.7a | \
  perl -ane 'if(!m:^;;;:){ s:(\S+)\(\d+\) :$1 :; s:  : :; print; }' | \
  perl -ane '@A = split(" ", $_); for ($n = 1; $n<@A;$n++) { $A[$n] =~ s/[0-9]//g; } print join(" ", @A) . "\n";' | \
  sort | uniq > $save/lexicon1_raw_nosil.txt || exit 1;

#cat eddie_data/rt09.ami.ihmtrain09.v3.dct | sort > $save/lexicon1_raw_nosil.txt

# limit the vocabulary to the predefined 50k words
wget -nv -O $save/wordlist.50k.gz http://www.openslr.org/resources/9/wordlist.50k.gz
gunzip -c $save/wordlist.50k.gz > $save/wordlist.50k
join $save/lexicon1_raw_nosil.txt $save/wordlist.50k > $save/lexicon1_raw_nosil_50k.txt

# Add prons for laughter, noise, oov
for w in `grep -v sil $save/silence_phones.txt`; do
  echo "[$w] $w"
done | cat - $save/lexicon1_raw_nosil_50k.txt > $save/lexicon2_raw_50k.txt || exit 1;

# add some specific words, those are only with 100 missing occurences or more
( echo "MM M"; \
  echo "HMM HH M"; \
  echo "MM-HMM M HH M"; \
  echo "COLOUR  K AH L ER"; \
  echo "COLOURS  K AH L ER Z"; \
  echo "REMOTES  R IH M OW T Z"; \
  echo "FAVOURITE F EY V ER IH T"; \
  echo "<unk> oov" ) | cat - $save/lexicon2_raw_50k.txt \
     | sort -u > $save/lexicon3_extra_50k.txt

cp $save/lexicon3_extra_50k.txt $save/lexicon.txt
rm $save/lexiconp.txt 2>/dev/null; # can confuse later script if this exists.

#############################################################################

#############################################################################


[ ! -f $save/lexicon.txt ] && exit 1;

echo "Dictionary preparation succeeded"

