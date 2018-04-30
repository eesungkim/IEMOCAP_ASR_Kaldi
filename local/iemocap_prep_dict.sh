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


# Make phones symbol-table (adding in silence and verbal and non-verbal noises at this point).
# We are adding suffixes _B, _E, _S for beginning, ending, and singleton phones.

# silence phones, one per line.
(echo SIL; echo SPN; echo NSN) > $save/silence_phones.txt
echo SIL > $save/optional_silence.txt
echo "optional_silence.txt file was generated."

# nonsilence phones; on each line is a list of phones that correspond really to the same base phone.
cat $save/cmudict/cmudict.0.7a.symbols | perl -ane 's:\r::; print;' | \
 perl -e 'while(<>){
  chop; m:^([^\d]+)(\d*)$: || die "Bad phone $_"; 
  $phones_of{$1} .= "$_ "; }
  foreach $list (values %phones_of) {print $list . "\n"; } ' \
  > $save/nonsilence_phones.txt || exit 1;
echo "nonsilence.txt file was generated."

# A few extra questions that will be added to those obtained by automatically clustering
# the "real" phones.  These ask about stress; there's also one for silence.
cat $save/silence_phones.txt| awk '{printf("%s ", $1);} END{printf "\n";}' > $save/extra_questions.txt || exit 1;
cat $save/nonsilence_phones.txt | perl -e 'while(<>){ foreach $p (split(" ", $_)) {
  $p =~ m:^([^\d]+)(\d*)$: || die "Bad phone $_"; $q{$2} .= "$p "; } } foreach $l (values %q) {print "$l\n";}' \
 >> $save/extra_questions.txt || exit 1;
echo "extra_questions.txt file was generated."


grep -v ';;;' $save/cmudict/cmudict.0.7a | \
 perl -ane 'if(!m:^;;;:){ s:(\S+)\(\d+\) :$1 :; print; }' \
  > $save/lexicon1_raw_nosil.txt || exit 1;

# Add to cmudict the silences, noises etc.

# the sort | uniq is to remove a duplicated pron from cmudict.
(echo '!SIL SIL'; echo '<SPOKEN_NOISE> SPN'; echo '<UNK> SPN'; echo '<NOISE> NSN'; ) | \
 cat - $save/lexicon1_raw_nosil.txt | sort | uniq > $save/lexicon2_raw.txt || exit 1;


# lexicon.txt is without the _B, _E, _S, _I markers.
# This is the input to wsj_format_data.sh
cp $save/lexicon2_raw.txt $save/lexicon.txt

rm $save/lexiconp.txt 2>/dev/null
echo "lexicon.txt file were generated."

echo "Dictionary preparation succeeded"

