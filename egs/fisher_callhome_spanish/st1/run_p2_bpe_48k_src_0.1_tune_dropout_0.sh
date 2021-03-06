#!/bin/bash

# Copyright 2018 Kyoto University (Hirofumi Inaguma)
#  Apache 2.0  (http://www.apache.org/licenses/LICENSE-2.0)

. ./path.sh || exit 1;
. ./cmd.sh || exit 1;

# general configuration
backend=pytorch # chainer or pytorch
stage=0         # start from 0 if you need to start from data preparation
stop_stage=100
ngpu=1          # number of gpus ("0" uses cpu, otherwise use gpu)
nj=4            # number of parallel jobs for decoding
debugmode=1
dumpdir=dump_sample_16k_bpe_48k_src_0.1   # directory to dump full features
N=0             # number of minibatches to be used (mainly for debugging). "0" uses all minibatches.
verbose=0       # verbose option
resume= # Resume the training from snapshot
seed=1          # seed to generate random number
sample_rate=16000 # it could be 16000, don't forget to change fbank/pitch.conf
# feature configuration
do_delta=false

preprocess_config=
# train_config=conf/train.yaml
train_config=conf/tuning/train_dual_encoder_conformer.yaml #conf/train.yaml
decode_config=conf/decode.yaml
# decode_config=conf/decode.yaml

# decoding parameter
trans_model=model.acc.best # set a model to be used for decoding: 'model.acc.best' or 'model.loss.best'

# model average realted (only for transformer)
n_average=5                  # the number of ST models to be averaged
use_valbest_average=true     # if true, the validation `n_average`-best ST models will be averaged.
                             # if false, the last `n_average` ST models will be averaged.
metric=bleu                  # loss/acc/bleu

# pre-training related
asr_model=
mt_model=

# preprocessing related
src_case=lc.rm
tgt_case=lc.rm
# tc: truecase
# lc: lowercase
# lc.rm: lowercase with punctuation removal

# Set this to somewhere where you want to put your data, or where
# someone else has already put it.  You'll want to change this
# if you're not on the CLSP grid.
sfisher_speech=/mnt/md0/user_jamfly/CORPUS/LDC2010S01
sfisher_transcripts=/mnt/md0/user_jamfly/CORPUS/LDC2010T04
split=local/splits/split_fisher

callhome_speech=/export/corpora/LDC/LDC96S35
callhome_transcripts=/export/corpora/LDC/LDC96T17
split_callhome=local/splits/split_callhome

# bpemode (unigram or bpe)
nbpe=1000
bpemode=bpe
phone_nbpe=48000
bpe_dropout=0
phone_bpe_dropout=0.1
# NOTE: nbpe=53 means character-level ST (lc.rm)
# NOTE: nbpe=66 means character-level ST (lc)
# NOTE: nbpe=98 means character-level ST (tc)

# exp tag
tag="fix_p2_bpe_48k_src_0.1_tune_dropout_0" # tag for managing experiments.

. utils/parse_options.sh || exit 1;

# Set bash to 'debug' mode, it will exit on :
# -e 'error', -u 'undefined variable', -o ... 'error in pipeline', -x 'print commands',
set -e
set -u
set -o pipefail

train_set=train_sp.en
train_set_prefix=train_sp
train_dev=train_dev.en
trans_set="fisher_dev.en fisher_dev2.en fisher_test.en"

# set training data split type, all, mid, low
# all is 160 hr, mid 40 hr, low 20 hr, respectively
split_type="mid"

# phone recognition system
phone_system="allophone"

# trans_set="fisher_dev.en fisher_dev2.en fisher_test.en callhome_devtest.en callhome_evltest.en"

if [ ${stage} -le 0 ] && [ ${stop_stage} -ge 0 ]; then
    ### Task dependent. You have to make data the following preparation part by yourself.
    ### But you can utilize Kaldi recipes in most cases
    echo "stage 0: Data Preparation"
    local/fsp_data_prep.sh ${sfisher_speech} ${sfisher_transcripts}
    # local/callhome_data_prep.sh ${callhome_speech} ${callhome_transcripts}

    # split data
    local/create_splits.sh ${split}
    # local/callhome_create_splits.sh ${split_callhome}

    # concatenate multiple utterances
    local/normalize_trans.sh ${sfisher_transcripts} ${callhome_transcripts} ${split_type}
fi

feat_tr_dir=${dumpdir}/${train_set}/delta${do_delta}; mkdir -p ${feat_tr_dir}
feat_dt_dir=${dumpdir}/${train_dev}/delta${do_delta}; mkdir -p ${feat_dt_dir}
if [ ${stage} -le 1 ] && [ ${stop_stage} -ge 1 ]; then
    # Task dependent. You have to design training and dev sets by yourself.
    # But you can utilize Kaldi recipes in most cases
    echo "stage 1: Feature Generation"
    # fbankdir=fbank
    # # Generate the fbank features; by default 80-dimensional fbanks with pitch on each frame
    # # for x in fisher_dev fisher_dev2 fisher_test callhome_devtest callhome_evltest; do
    # for x in fisher_dev fisher_dev2 fisher_test; do
    #     # it could upsample audio from 8k to 8k to make a recipe consistent with others
    #     # dont forget to change sample_rate
    #     sed -i.bak -e "s/$/ sox -R -t wav - -t wav - rate ${sample_rate} dither | /" data/${x}/wav.scp

    #     steps/make_fbank_pitch.sh --cmd "$train_cmd" --nj 32 --write_utt2num_frames true \
    #         data/${x} exp/make_fbank/${x} ${fbankdir}
    # done

    # # speed-perturbed. data/${train_set_ori} is the orignal and data/${train_set} is the augmented
    # sed -i.bak -e "s/$/ sox -R -t wav - -t wav - rate ${sample_rate} dither | /" data/fisher_train/wav.scp
    # utils/perturb_data_dir_speed.sh 0.9 data/fisher_train data/temp1
    # utils/perturb_data_dir_speed.sh 1.0 data/fisher_train data/temp2
    # utils/perturb_data_dir_speed.sh 1.1 data/fisher_train data/temp3
    # utils/combine_data.sh --extra-files utt2uniq data/train_sp data/temp1 data/temp2 data/temp3
    # rm -r data/temp1 data/temp2 data/temp3
    # steps/make_fbank_pitch.sh --cmd "$train_cmd" --nj 32 --write_utt2num_frames true \
    #     data/train_sp exp/make_fbank/train_sp ${fbankdir}
    # utils/fix_data_dir.sh data/train_sp
    # utils/validate_data_dir.sh data/train_sp

    # for lang in es en; do
    #     awk -v p="sp0.9-" '{printf("%s %s%s\n", $1, p, $1);}' data/fisher_train/utt2spk > data/train_sp/utt_map
    #     utils/apply_map.pl -f 1 data/train_sp/utt_map <data/fisher_train/text.tc.${lang} >data/train_sp/text.tc.${lang}
    #     utils/apply_map.pl -f 1 data/train_sp/utt_map <data/fisher_train/text.lc.${lang} >data/train_sp/text.lc.${lang}
    #     utils/apply_map.pl -f 1 data/train_sp/utt_map <data/fisher_train/text.lc.rm.${lang} >data/train_sp/text.lc.rm.${lang}
    #     awk -v p="sp1.0-" '{printf("%s %s%s\n", $1, p, $1);}' data/fisher_train/utt2spk > data/train_sp/utt_map
    #     utils/apply_map.pl -f 1 data/train_sp/utt_map <data/fisher_train/text.tc.${lang} >>data/train_sp/text.tc.${lang}
    #     utils/apply_map.pl -f 1 data/train_sp/utt_map <data/fisher_train/text.lc.${lang} >>data/train_sp/text.lc.${lang}
    #     utils/apply_map.pl -f 1 data/train_sp/utt_map <data/fisher_train/text.lc.rm.${lang} >>data/train_sp/text.lc.rm.${lang}
    #     awk -v p="sp1.1-" '{printf("%s %s%s\n", $1, p, $1);}' data/fisher_train/utt2spk > data/train_sp/utt_map
    #     utils/apply_map.pl -f 1 data/train_sp/utt_map <data/fisher_train/text.tc.${lang} >>data/train_sp/text.tc.${lang}
    #     utils/apply_map.pl -f 1 data/train_sp/utt_map <data/fisher_train/text.lc.${lang} >>data/train_sp/text.lc.${lang}
    #     utils/apply_map.pl -f 1 data/train_sp/utt_map <data/fisher_train/text.lc.rm.${lang} >>data/train_sp/text.lc.rm.${lang}
    # done

    # # Divide into source and target languages
    # # for x in ${train_set_prefix} fisher_dev fisher_dev2 fisher_test callhome_devtest callhome_evltest; do
    # for x in ${train_set_prefix} fisher_dev fisher_dev2 fisher_test; do
    #     local/divide_lang.sh ${x}
    # done

    # for lang in es en; do
    #     if [ -d data/train_dev.${lang} ];then
    #         rm -rf data/train_dev.${lang}
    #     fi
    #     cp -rf data/fisher_dev.${lang} data/train_dev.${lang}
    # done
    # # NOTE: do not use callhome_train for the training set

    # for x in ${train_set_prefix} train_dev; do
    #     # remove utt having more than 3000 frames
    #     # remove utt having more than 400 characters
    #     for lang in es en; do
    #         remove_longshortdata.sh --maxframes 3000 --maxchars 400 data/${x}.${lang} data/${x}.${lang}.tmp
    #     done

    #     # Match the number of utterances between source and target languages
    #     # extract commocn lines
    #     cut -f 1 -d " " data/${x}.es.tmp/text > data/${x}.en.tmp/reclist1
    #     cut -f 1 -d " " data/${x}.en.tmp/text > data/${x}.en.tmp/reclist2
    #     comm -12 data/${x}.en.tmp/reclist1 data/${x}.en.tmp/reclist2 > data/${x}.en.tmp/reclist

    #     for lang in es en; do
    #         reduce_data_dir.sh data/${x}.${lang}.tmp data/${x}.en.tmp/reclist data/${x}.${lang}
    #         utils/fix_data_dir.sh --utt_extra_files "text.tc text.lc text.lc.rm" data/${x}.${lang}
    #     done
    #     rm -rf data/${x}.*.tmp
    # done

    # # compute global CMVN
    # compute-cmvn-stats scp:data/${train_set}/feats.scp data/${train_set}/cmvn.ark

    # # dump features for training
    # if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d ${feat_tr_dir}/storage ]; then
    #   utils/create_split_dir.pl \
    #       /export/b{14,15,16,17}/${USER}/espnet-data/egs/fisher_callhome_spanish/st1/dump/${train_set}/delta${do_delta}/storage \
    #       ${feat_tr_dir}/storage
    # fi
    # if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d ${feat_dt_dir}/storage ]; then
    #   utils/create_split_dir.pl \
    #       /export/b{14,15,16,17}/${USER}/espnet-data/egs/fisher_callhome_spanish/st1/dump/${train_dev}/delta${do_delta}/storage \
    #       ${feat_dt_dir}/storage
    # fi
    # dump.sh --cmd "$train_cmd" --nj 80 --do_delta $do_delta \
    #     data/${train_set}/feats.scp data/${train_set}/cmvn.ark exp/dump_feats/${train_set} ${feat_tr_dir}
    # dump.sh --cmd "$train_cmd" --nj 32 --do_delta $do_delta \
    #     data/${train_dev}/feats.scp data/${train_set}/cmvn.ark exp/dump_feats/${train_dev} ${feat_dt_dir}
    # for ttask in ${trans_set}; do
    #     feat_trans_dir=${dumpdir}/${ttask}/delta${do_delta}; mkdir -p ${feat_trans_dir}
    #     dump.sh --cmd "$train_cmd" --nj 32 --do_delta $do_delta \
    #         data/${ttask}/feats.scp data/${train_set}/cmvn.ark exp/dump_feats/trans/${ttask} \
    #         ${feat_trans_dir}
    # done
    # phone recognizing
    echo "recognizing phone...."
    for dataset in fisher_dev.es fisher_dev2.es fisher_test.es train_sp.es train_dev.es; do
        python local/phone_recognition.py \
          --phone-path data_sample_16k_bpe_48k_src_0.1/${dataset}/phone \
          --wav-scp-path data_sample_16k_bpe_48k_src_0.1/${dataset}/wav.scp \
          --segments data_sample_16k_bpe_48k_src_0.1/${dataset}/segments \
          --dataset ${dataset} \
          --phone-system ${phone_system} \
          --number-of-worker ${nj} > data_sample_16k_bpe_48k_src_0.1/${dataset}/phone.log
    done
    rm -rf ${phone_system}
fi

dict=data_sample_16k_bpe_48k_src_0.1/lang_1spm/${train_set}_${bpemode}${nbpe}_units_${tgt_case}.txt
phone_dict=data_sample_16k_bpe_48k_src_0.1/lang_1spm/phone.txt
phone_transform_dict=data_sample_16k_bpe_48k_src_0.1/lang_1spm/phone_map.txt
nlsyms=data_sample_16k_bpe_48k_src_0.1/lang_1spm/${train_set}_non_lang_syms_${tgt_case}.txt
bpemodel=data_sample_16k_bpe_48k_src_0.1/lang_1spm/${train_set}_${bpemode}${nbpe}_${tgt_case}
phone_bpemodel=data_sample_16k_bpe_48k_src_0.1/lang_1spm/${train_set}_${bpemode}${nbpe}_phone

echo "dictionary: ${dict}"
if [ ${stage} -le 2 ] && [ ${stop_stage} -ge 2 ]; then
    # Task dependent. You have to check non-linguistic symbols used in the corpus.
    echo "stage 2: Dictionary and Json Data Preparation"
    mkdir -p data_sample_16k_bpe_48k_src_0.1/lang_1spm/

    echo "make a non-linguistic symbol list for all languages"
    grep sp1.0 data_sample_16k_bpe_48k_src_0.1/${train_set_prefix}.*/text.${tgt_case} | cut -f 2- -d' ' | grep -o -P '&[^;]*;' | sort | uniq > ${nlsyms}
    cat ${nlsyms}

    echo "make a joint source and target dictionary"
    echo "<unk> 1" > ${dict} # <unk> must be 1, 0 will be used for "blank" in CTC
    offset=$(wc -l < ${dict})

    grep sp1.0 data_sample_16k_bpe_48k_src_0.1/${train_set_prefix}.*/text.${tgt_case} | cut -f 2- -d' ' | grep -v -e '^\s*$' > data_sample_16k_bpe_48k_src_0.1/lang_1spm/input.txt
    spm_train --user_defined_symbols="$(tr "\n" "," < ${nlsyms})" --input=data_sample_16k_bpe_48k_src_0.1/lang_1spm/input.txt --vocab_size=${nbpe} --model_type=${bpemode} --model_prefix=${bpemodel} --input_sentence_size=100000000 --character_coverage=1.0
    spm_encode --model=${bpemodel}.model --output_format=piece < data_sample_16k_bpe_48k_src_0.1/lang_1spm/input.txt | tr ' ' '\n' | sort | uniq | awk -v offset=${offset} '{print $0 " " NR+offset}' >> ${dict}
    wc -l ${dict}

    echo "<unk> 1" > ${phone_dict}
    phone_offset=$(wc -l < ${phone_dict})
    
    # phone
    grep sp1.0 data_sample_16k_bpe_48k_src_0.1/${train_set_prefix}.es/phone | cut -f 2- -d' ' | grep -v -e '^\s*$' > data_sample_16k_bpe_48k_src_0.1/lang_1spm/phone_input.txt
    cat < data_sample_16k_bpe_48k_src_0.1/lang_1spm/phone_input.txt | tr ' ' '\n' | sort | uniq | awk -v offset=${phone_offset} '{print $0 " " NR+offset}' >> ${phone_dict}

    # phone bpe
    echo "<unk> 1" > ${phone_transform_dict}
    phone_transform_offset=$(wc -l < ${phone_transform_dict})

    python local/phone_mapping.py --phone-dict=${phone_dict} --phone-input=data_sample_16k_bpe_48k_src_0.1/lang_1spm/phone_input.txt >> data_sample_16k_bpe_48k_src_0.1/lang_1spm/phone_transform.txt

    spm_train --user_defined_symbols="$(tr "\n" "," < ${nlsyms})" --input=data_sample_16k_bpe_48k_src_0.1/lang_1spm/phone_transform.txt --vocab_size=${phone_nbpe} --model_type=${bpemode} --model_prefix=${phone_bpemodel} --input_sentence_size=100000000 --character_coverage=1.0
    spm_encode --model=${phone_bpemodel}.model --output_format=piece < data_sample_16k_bpe_48k_src_0.1/lang_1spm/phone_transform.txt | tr ' ' '\n' | sort | uniq | awk -v offset=${phone_transform_offset} '{print $0 " " NR+offset}' >> ${phone_transform_dict}

    echo "make json files"
    # only training set apply bpe-dropout
    data2json.sh --nj 16 --feat ${feat_tr_dir}/feats.scp --text data_sample_16k_bpe_48k_src_0.1/${train_set}/text.${tgt_case} --bpecode ${bpemodel}.model --bpe_dropout ${bpe_dropout} --lang en \
        data_sample_16k_bpe_48k_src_0.1/${train_set} ${dict} > ${feat_tr_dir}/data_${bpemode}${nbpe}.${src_case}_${tgt_case}.json
    data2json.sh --feat ${feat_dt_dir}/feats.scp --text data_sample_16k_bpe_48k_src_0.1/${train_dev}/text.${tgt_case} --bpecode ${bpemodel}.model --lang en \
        data_sample_16k_bpe_48k_src_0.1/${train_dev} ${dict} > ${feat_dt_dir}/data_${bpemode}${nbpe}.${src_case}_${tgt_case}.json
    for ttask in ${trans_set}; do
        feat_trans_dir=${dumpdir}/${ttask}/delta${do_delta}
        data2json.sh --feat ${feat_trans_dir}/feats.scp --text data_sample_16k_bpe_48k_src_0.1/${ttask}/text.${tgt_case} --bpecode ${bpemodel}.model --lang en \
            data_sample_16k_bpe_48k_src_0.1/${ttask} ${dict} > ${feat_trans_dir}/data_${bpemode}${nbpe}.${src_case}_${tgt_case}.json
    done

    # Fisher has 4 references per utterance
    for ttask in fisher_dev.en fisher_dev2.en fisher_test.en; do
        feat_trans_dir=${dumpdir}/${ttask}/delta${do_delta}
        for no in 1 2 3; do
            data2json.sh --text data_sample_16k_bpe_48k_src_0.1/${ttask}/text.${tgt_case}.${no} --feat ${feat_trans_dir}/feats.scp --bpecode ${bpemodel}.model --lang en \
                data_sample_16k_bpe_48k_src_0.1/${ttask} ${dict} > ${feat_trans_dir}/data_${bpemode}${nbpe}_${no}.${tgt_case}.json
        done
    done

    # phone bpe encode for all of different dataset
    for x in ${train_dev} fisher_dev.en fisher_dev2.en fisher_test.en; do
        data_dir=data_sample_16k_bpe_48k_src_0.1/$(echo ${x} | cut -f 1 -d ".").es
        # dev/test set don't not need bpe-dropout
        python local/phone_bpe.py --phone-path=${data_dir}/phone --phone-dict=${phone_dict} --bpe-model=${phone_bpemodel}.model >> ${data_dir}/phone_bpe
    done

    train_data_dir=data_sample_16k_bpe_48k_src_0.1/$(echo ${train_set} | cut -f 1 -d ".").es
    python local/phone_bpe.py --phone-path=${train_data_dir}/phone --phone-dict=${phone_dict} --bpe-model=${phone_bpemodel}.model --dropout-prob=${phone_bpe_dropout} >> ${train_data_dir}/phone_bpe

    # update json (add source references and phone sequence)
    for x in ${train_set} ${train_dev} fisher_dev.en fisher_dev2.en fisher_test.en; do
        feat_dir=${dumpdir}/${x}/delta${do_delta}
        data_dir=data_sample_16k_bpe_48k_src_0.1/$(echo ${x} | cut -f 1 -d ".").es

        # update_json.sh --text ${data_dir}/text.${src_case} --bpecode ${bpemodel}.model \
        #     ${feat_dir}/data_${bpemode}${nbpe}.${src_case}_${tgt_case}.json ${data_dir} ${dict} "char"

        # update_json.sh --text ${data_dir}/phone \
        #   ${feat_dir}/data_${bpemode}${nbpe}.${src_case}_${tgt_case}.json ${data_dir} ${phone_dict} "phn"

        update_json.sh --text ${data_dir}/phone \
          ${feat_dir}/data_${bpemode}${nbpe}.${src_case}_${tgt_case}.json ${data_dir} ${phone_dict} "phn"

        update_json.sh --text ${data_dir}/phone_bpe \
            ${feat_dir}/data_${bpemode}${nbpe}.${src_case}_${tgt_case}.json ${data_dir} ${phone_transform_dict} "phn"
    done
    for x in fisher_dev.en fisher_dev2.en fisher_test.en; do
        feat_dir=${dumpdir}/${x}/delta${do_delta}
        data_dir=data_sample_16k_bpe_48k_src_0.1/$(echo ${x} | cut -f 1 -d ".").es

        for no in 1 2 3; do
            # update_json.sh --text ${data_dir}/text.${src_case} --bpecode ${bpemodel}.model \
            #     ${feat_dir}/data_${bpemode}${nbpe}_${no}.${tgt_case}.json ${data_dir} ${dict} "char"

            # update_json.sh --text ${data_dir}/phone \
            #   ${feat_dir}/data_${bpemode}${nbpe}_${no}.${tgt_case}.json ${data_dir} ${phone_dict} "phn"

            update_json.sh --text ${data_dir}/phone \
              ${feat_dir}/data_${bpemode}${nbpe}_${no}.${tgt_case}.json ${data_dir} ${phone_dict} "phn"

            update_json.sh --text ${data_dir}/phone_bpe \
                ${feat_dir}/data_${bpemode}${nbpe}_${no}.${tgt_case}.json ${data_dir} ${phone_transform_dict} "phn"
        done
    done

fi

# NOTE: skip stage 3: LM Preparation

if [ -z ${tag} ]; then
    expname=${train_set}_${tgt_case}_${backend}_$(basename ${train_config%.*})_${bpemode}${nbpe}
    if ${do_delta}; then
        expname=${expname}_delta
    fi
    if [ -n "${preprocess_config}" ]; then
        expname=${expname}_$(basename ${preprocess_config%.*})
    fi
    if [ -n "${asr_model}" ]; then
        expname=${expname}_asrtrans
    fi
    if [ -n "${mt_model}" ]; then
        expname=${expname}_mttrans
    fi
else
    expname=${train_set}_${tgt_case}_${backend}_${tag}
fi
expdir=exp/${expname}
mkdir -p ${expdir}

if [ ${stage} -le 4 ] && [ ${stop_stage} -ge 4 ]; then
    echo "stage 4: Network Training"

    # --train-json ${feat_tr_dir}/data_${bpemode}${nbpe}.${src_case}_${tgt_case}.json \
    # --valid-json ${feat_dt_dir}/data_${bpemode}${nbpe}.${src_case}_${tgt_case}.json \

    # --train-json ${feat_tr_dir}/data_${bpemode}${nbpe}.test.json \
    # --valid-json ${feat_dt_dir}/data_${bpemode}${nbpe}.test.json \
    DEBUG=false
    if [ ${DEBUG} == false ]; then
        train_json=${feat_tr_dir}/data_${bpemode}${nbpe}.${src_case}_${tgt_case}.json
        valid_json=${feat_dt_dir}/data_${bpemode}${nbpe}.${src_case}_${tgt_case}.json 
    else
        train_json=${feat_tr_dir}/data_${bpemode}${nbpe}.test.json
        valid_json=${feat_dt_dir}/data_${bpemode}${nbpe}.test.json
    fi

    ${cuda_cmd} --gpu ${ngpu} ${expdir}/train.log \
        st_train.py \
        --config ${train_config} \
        --preprocess-conf ${preprocess_config} \
        --ngpu ${ngpu} \
        --backend ${backend} \
        --outdir ${expdir}/results \
        --tensorboard-dir tensorboard/${expname} \
        --debugmode ${debugmode} \
        --dict ${dict} \
        --debugdir ${expdir} \
        --minibatches ${N} \
        --seed ${seed} \
        --verbose ${verbose} \
        --resume ${resume} \
        --train-json ${train_json} \
        --valid-json ${valid_json} \
        --enc-init ${asr_model} \
        --dec-init ${mt_model} \
        --fbank-fs ${sample_rate}
fi

if [ ${stage} -le 5 ] && [ ${stop_stage} -ge 5 ]; then
    echo "stage 5: Decoding"
    if [[ $(get_yaml.py ${train_config} model-module) = *transformer* ]] || \
       [[ $(get_yaml.py ${train_config} model-module) = *conformer* ]]; then
        # Average ST models
        if ${use_valbest_average}; then
            trans_model=model.val${n_average}.avg.best
            opt="--log ${expdir}/results/log --metric ${metric}"
        else
            trans_model=model.last${n_average}.avg.best
            opt="--log"
        fi
        average_checkpoints.py \
            ${opt} \
            --backend ${backend} \
            --snapshots ${expdir}/results/snapshot.ep.* \
            --out ${expdir}/results/${trans_model} \
            --num ${n_average}
    fi

    pids=() # initialize pids
    for ttask in ${trans_set}; do
    (
        decode_dir=decode_${ttask}_$(basename ${decode_config%.*})
        feat_trans_dir=${dumpdir}/${ttask}/delta${do_delta}

        # split data
        splitjson.py --parts ${nj} ${feat_trans_dir}/data_${bpemode}${nbpe}.${src_case}_${tgt_case}.json

        #### use CPU for decoding
        ngpu=0

        ${decode_cmd} JOB=1:${nj} ${expdir}/${decode_dir}/log/decode.JOB.log \
            st_trans.py \
            --config ${decode_config} \
            --ngpu ${ngpu} \
            --backend ${backend} \
            --batchsize 0 \
            --trans-json ${feat_trans_dir}/split${nj}utt/data_${bpemode}${nbpe}.JOB.json \
            --result-label ${expdir}/${decode_dir}/data.JOB.json \
            --model ${expdir}/results/${trans_model}

        # Fisher has 4 references per utterance
        if [ ${ttask} = "fisher_dev.en" ] || [ ${ttask} = "fisher_dev2.en" ] || [ ${ttask} = "fisher_test.en" ]; then
            for no in 1 2 3; do
                cp ${feat_trans_dir}/data_${bpemode}${nbpe}_${no}.${tgt_case}.json ${expdir}/${decode_dir}/data_ref${no}.json
            done
        fi

        local/score_bleu.sh --case ${tgt_case} --set ${ttask} --bpe ${nbpe} --bpemodel ${bpemodel}.model \
            ${expdir}/${decode_dir} ${dict}
    ) &
    pids+=($!) # store background pids
    done
    i=0; for pid in "${pids[@]}"; do wait ${pid} || ((++i)); done
    [ ${i} -gt 0 ] && echo "$0: ${i} background jobs are failed." && false
    echo "Finished"
fi
