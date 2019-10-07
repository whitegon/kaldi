#!/bin/bash
. ./cmd.sh
. ./path.sh
set -e
mfccdir=`pwd`/mfcc
sre18_trials=data/sre18_dev_test/trials
sre18_scores=exp/scores/sre18_dev_scores
sre18_scores_adapt=exp/scores/sre18_dev_scores_adapt
nnet_dir=exp/xvector_nnet
stage=7
job=100
if [ $stage -le 0 ]; then
  #utils/combine_data.sh data/fisher data/fisher1 data/fisher2
  utils/combine_data.sh data/voxceleb data/voxceleb2_train data/voxceleb1_train data/voxceleb2_test data/voxceleb1_test 
  #utils/combine_data.sh data/swbd data/swbd_cellular1_train data/swbd_cellular2_train data/swbd2_phase1_train data/swbd2_phase2_train data/swbd2_phase3_train
  #utils/combine_data.sh data/sre data/sre2004 data/sre2005_train data/sre2005_test data/sre2006_train data/sre2006_test_1 data/sre2006_test_2 data/sre08 data/sre10 data/mx6
fi

#sre18_dev_enroll sre18_dev_test sre18_dev_unlabeled sre swbd fisher voxceleb

if [ $stage -le 1 ]; then
  for name in sre18_dev_enroll sre18_dev_test sre18_dev_unlabeled voxceleb; do
    utils/validate_data_dir.sh --no-text --no-feats data/${name}
    utils/fix_data_dir.sh data/${name}
    utils/utt2spk_to_spk2utt.pl data/${name}/utt2spk > data/${name}/spk2utt
    #steps/make_fbank_pitch.sh --write-utt2num-frames true --nj $job --cmd "$train_cmd" data/${name} $mfccdir $mfccdir
    steps/make_mfcc.sh --write-utt2num-frames true --mfcc-config conf/mfcc.conf --nj $job --cmd "$train_cmd" data/${name} $mfccdir $mfccdir
    #steps/make_plp.sh --write-utt2num-frames true --plp-config conf/plp.conf --nj $job --cmd "$train_cmd" data/${name} $mfccdir $mfccdir
    utils/fix_data_dir.sh data/${name}
    sid/compute_vad_decision.sh --nj $job --cmd "$train_cmd" data/${name} $mfccdir $mfccdir
    utils/fix_data_dir.sh data/${name}
  done
fi

#sre18_dev_unlabeled sre swbd fisher voxceleb


if [ $stage -le 2 ]; then

  


  utils/combine_data.sh --extra-files "utt2num_frames" data/atr data/sre18_dev_unlabeled_combined
  utils/fix_data_dir.sh data/atr
	 
  for name in voxceleb; do #16k
   frame_shift=0.01
   awk -v frame_shift=$frame_shift '{print $1, $2*frame_shift;}' data/${name}/utt2num_frames > data/${name}/reco2dur
   rvb_opts=()
   rvb_opts+=(--rir-set-parameters "0.5, RIRS_NOISES/simulated_rirs/smallroom/rir_list")
   rvb_opts+=(--rir-set-parameters "0.5, RIRS_NOISES/simulated_rirs/mediumroom/rir_list")

   python steps/data/reverberate_data_dir.py \
     "${rvb_opts[@]}" \
     --speech-rvb-probability 1 \
     --pointsource-noise-addition-probability 0 \
     --isotropic-noise-addition-probability 0 \
     --num-replications 1 \
     --source-sampling-rate 16000 \
     data/${name} data/${name}_reverb
   cp data/${name}/vad.scp data/${name}_reverb/
   utils/copy_data_dir.sh --utt-suffix "-reverb" data/${name}_reverb data/${name}_reverb.new 
   rm -rf data/${name}_reverb
   mv data/${name}_reverb.new data/${name}_reverb

   python steps/data/augment_data_dir.py --utt-suffix "noise" --fg-interval 1 --fg-snrs "15:10:5:0" --fg-noise-dir "data/musan16k_noise" data/${name} data/${name}_noise
   python steps/data/augment_data_dir.py --utt-suffix "music" --bg-snrs "15:10:8:5" --num-bg-noises "1" --bg-noise-dir "data/musan16k_music" data/${name} data/${name}_music
   python steps/data/augment_data_dir.py --utt-suffix "babble" --bg-snrs "20:17:15:13" --num-bg-noises "3:4:5:6:7" --bg-noise-dir "data/musan16k_speech" data/${name} data/${name}_babble

   utils/combine_data.sh data/${name}_aug data/${name}_reverb data/${name}_noise data/${name}_music data/${name}_babble

   utils/fix_data_dir.sh data/${name}_aug
   #steps/make_fbank_pitch.sh --write-utt2num-frames true --nj $job --cmd "$train_cmd" data/${name}_aug $mfccdir $mfccdir
   steps/make_mfcc.sh --write-utt2num-frames true --mfcc-config conf/mfcc.conf --nj $job --cmd "$train_cmd" data/${name}_aug $mfccdir $mfccdir
   #steps/make_plp.sh --write-utt2num-frames true --plp-config conf/plp.conf --nj $job --cmd "$train_cmd" data/${name}_aug $mfccdir $mfccdir
   utils/perturb_data_dir_speed.sh 0.9 data/${name} data/${name}_p1
   utils/perturb_data_dir_speed.sh 1.1 data/${name} data/${name}_p2
   utils/combine_data.sh data/${name}_p data/${name}_p1 data/${name}_p2
   utils/fix_data_dir.sh data/${name}_p
   #steps/make_fbank_pitch.sh --write-utt2num-frames true --nj $job --cmd "$train_cmd" data/${name}_p $mfccdir $mfccdir
   steps/make_mfcc.sh --write-utt2num-frames true --mfcc-config conf/mfcc.conf --nj $job --cmd "$train_cmd" data/${name}_p $mfccdir $mfccdir
   #steps/make_plp.sh --write-utt2num-frames true --plp-config conf/plp.conf --nj $job --cmd "$train_cmd" data/${name}_p $mfccdir $mfccdir
   sid/compute_vad_decision.sh --nj $job --cmd "$train_cmd" data/${name}_p $mfccdir $mfccdir
   utils/fix_data_dir.sh data/${name}_p
   utils/combine_data.sh data/${name}_combined data/${name}_aug data/${name}_p data/${name}
   utils/fix_data_dir.sh data/${name}_combined
  done

  utils/combine_data.sh --extra-files "utt2num_frames" data/atr data/voxceleb_combined
  utils/combine_data.sh --extra-files "utt2num_frames" data/atr data/voxceleb data/voxceleb_noise
  utils/fix_data_dir.sh data/atr


  utils/combine_data.sh --extra-files "utt2num_frames" data/atr data/voxceleb
  utils/fix_data_dir.sh data/atr

fi


if [ $stage -le 3 ]; then

	
  local/nnet3/xvector/prepare_feats_for_egs.sh --nj $job --cmd "$train_cmd" data/atr data/atr_no_sil exp/atr_no_sil
  utils/fix_data_dir.sh data/atr_no_sil
  min_len=400
  mv data/atr_no_sil/utt2num_frames data/atr_no_sil/utt2num_frames.bak
  awk -v min_len=${min_len} '$2 > min_len {print $1, $2}' data/atr_no_sil/utt2num_frames.bak > data/atr_no_sil/utt2num_frames
  utils/filter_scp.pl data/atr_no_sil/utt2num_frames data/atr_no_sil/utt2spk > data/atr_no_sil/utt2spk.new
  mv data/atr_no_sil/utt2spk.new data/atr_no_sil/utt2spk
  utils/fix_data_dir.sh data/atr_no_sil
  min_num_utts=8
  awk '{print $1, NF-1}' data/atr_no_sil/spk2utt > data/atr_no_sil/spk2num
  awk -v min_num_utts=${min_num_utts} '$2 >= min_num_utts {print $1, $2}' data/atr_no_sil/spk2num | utils/filter_scp.pl - data/atr_no_sil/spk2utt > data/atr_no_sil/spk2utt.new
  mv data/atr_no_sil/spk2utt.new data/atr_no_sil/spk2utt
  utils/spk2utt_to_utt2spk.pl data/atr_no_sil/spk2utt > data/atr_no_sil/utt2spk
  utils/filter_scp.pl data/atr_no_sil/utt2spk data/atr_no_sil/utt2num_frames > data/atr_no_sil/utt2num_frames.new
  mv data/atr_no_sil/utt2num_frames.new data/atr_no_sil/utt2num_frames
  utils/fix_data_dir.sh data/atr_no_sil

fi

local/nnet3/xvector/run_xvector.sh --stage $stage --train-stage -1 --data data/atr_no_sil --nnet-dir $nnet_dir --egs-dir $nnet_dir/egs

#sre18_dev_enroll sre18_dev_test sre18_dev_unlabeled_combined sre_combined
#sre18_dev_enroll sre18_dev_test sre18_dev_unlabeled

if [ $stage -le 7 ]; then
  for name in voxceleb ; do
    sid/nnet3/xvector/extract_xvectors.sh --cmd "$train_cmd" --nj $job $nnet_dir data/${name} $nnet_dir/xvectors_${name}
  done
fi
if [ $stage -le 8 ]; then
  $train_cmd log/compute_mean.log ivector-mean scp:$nnet_dir/xvectors_sre18_dev_unlabeled/xvector.scp $nnet_dir/mean.vec || exit 1;
  lda_dim=150
  $train_cmd log/lda.log ivector-compute-lda --total-covariance-factor=0.0 --dim=$lda_dim "ark:ivector-subtract-global-mean scp:$nnet_dir/xvectors_voxceleb/xvector.scp ark:- |" ark:data/voxceleb/utt2spk $nnet_dir/transform.mat || exit 1;
  $train_cmd log/plda.log ivector-compute-plda ark:data/voxceleb/spk2utt "ark:ivector-subtract-global-mean scp:$nnet_dir/xvectors_voxceleb/xvector.scp ark:- | transform-vec $nnet_dir/transform.mat ark:- ark:- | ivector-normalize-length ark:-  ark:- |" $nnet_dir/plda || exit 1;
  $train_cmd log/plda_adapt.log ivector-adapt-plda --within-covar-scale=0.75 --between-covar-scale=0.25 $nnet_dir/plda "ark:ivector-subtract-global-mean scp:$nnet_dir/xvectors_sre18_dev_unlabeled/xvector.scp ark:- | transform-vec $nnet_dir/transform.mat ark:- ark:- | ivector-normalize-length ark:- ark:- |" $nnet_dir/plda_adapt || exit 1;
fi
if [ $stage -le 9 ]; then
  $train_cmd log/sre18_dev_scoring.log \
    ivector-plda-scoring --normalize-length=true \
    --num-utts=ark:$nnet_dir/xvectors_sre18_dev_enroll/num_utts.ark \
    "ivector-copy-plda --smoothing=0.0 $nnet_dir/plda - |" \
    "ark:ivector-mean ark:data/sre18_dev_enroll/spk2utt scp:$nnet_dir/xvectors_sre18_dev_enroll/xvector.scp ark:- | ivector-subtract-global-mean $nnet_dir/mean.vec ark:- ark:- | transform-vec $nnet_dir/transform.mat ark:- ark:- | ivector-normalize-length ark:- ark:- |" \
    "ark:ivector-subtract-global-mean $nnet_dir/mean.vec scp:$nnet_dir/xvectors_sre18_dev_test/xvector.scp ark:- | transform-vec $nnet_dir/transform.mat ark:- ark:- | ivector-normalize-length ark:- ark:- |" \
    "cat '$sre18_trials' | cut -d\  --fields=1,2 |" $sre18_scores || exit 1;
  eer=`compute-eer <(python3 local/prepare_for_eer.py $sre18_trials $sre18_scores) 2> /dev/null`
  echo "eer: $eer"
  mindcf1=`python sid/compute_min_dcf.py --p-target 0.01 $sre18_scores $sre18_trials 2> /dev/null`
  mindcf2=`python sid/compute_min_dcf.py --p-target 0.005 $sre18_scores $sre18_trials 2> /dev/null`
  echo "minDCF(p-target=0.01): $mindcf1"
  echo "minDCF(p-target=0.005): $mindcf2"
fi
if [ $stage -le 10 ]; then
  $train_cmd log/sre18_dev_scoring_adapt.log \
    ivector-plda-scoring --normalize-length=true \
    --num-utts=ark:$nnet_dir/xvectors_sre18_dev_enroll/num_utts.ark \
    "ivector-copy-plda --smoothing=0.0 $nnet_dir/plda_adapt - |" \
    "ark:ivector-mean ark:data/sre18_dev_enroll/spk2utt scp:$nnet_dir/xvectors_sre18_dev_enroll/xvector.scp ark:- | ivector-subtract-global-mean $nnet_dir/mean.vec ark:- ark:- | transform-vec $nnet_dir/transform.mat ark:- ark:- | ivector-normalize-length ark:- ark:- |" \
    "ark:ivector-subtract-global-mean $nnet_dir/mean.vec scp:$nnet_dir/xvectors_sre18_dev_test/xvector.scp ark:- | transform-vec $nnet_dir/transform.mat ark:- ark:- | ivector-normalize-length ark:- ark:- |" \
    "cat '$sre18_trials' | cut -d\  --fields=1,2 |" $sre18_scores_adapt || exit 1;
  eer=`compute-eer <(python3 local/prepare_for_eer.py $sre18_trials $sre18_scores_adapt) 2> /dev/null`
  echo "eer: $eer"
  mindcf1=`python sid/compute_min_dcf.py --p-target 0.01 $sre18_scores_adapt $sre18_trials 2> /dev/null`
  mindcf2=`python sid/compute_min_dcf.py --p-target 0.005 $sre18_scores_adapt $sre18_trials 2> /dev/null`
  echo "minDCF(p-target=0.01): $mindcf1"
  echo "minDCF(p-target=0.005): $mindcf2"
fi

