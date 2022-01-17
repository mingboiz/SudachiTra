#!/bin/bash
set -eu

# check arg
# current script work with single dataset
if [ $# -lt 1 ] ; then
    echo "Provide dataset name: [amazon, rcqa, kuci]."
    exit 1
fi
DATASET=$1

# set your own dir
MODEL_ROOT="./bert"
DATASET_ROOT="./datasets"
OUTPUT_ROOT="./out"

# model to search
MODEL_NAMES=(
  "tohoku"
  "kyoto"
  "nict"
  "chitra_surface"
  "chitra_normalized_and_surface"
  "chitra_normalized_conjugation"
  "chitra_normalized"
)

DATASETS=("amazon" "rcqa" "kuci")

# Hyperparameters from Appendix A.3, Devlin et al., 2019
BATCHES=(16 32)
LRS=(5e-5 3e-5 2e-5)
EPOCHS=(4)


declare -A MODEL_DIRS=(
  ["tohoku"]="cl-tohoku/bert-base-japanese-whole-word-masking"
  ["kyoto"]="${MODEL_ROOT}/Japanese_L-12_H-768_A-12_E-30_BPE_WWM_transformers"
  ["nict"]="${MODEL_ROOT}/NICT_BERT-base_JapaneseWikipedia_32K_BPE"
  ["chitra_surface"]="${MODEL_ROOT}/Wikipedia_surface/phase_2"
  ["chitra_normalized_and_surface"]="${MODEL_ROOT}/Wikipedia_normalized_and_surface/phase_2"
  ["chitra_normalized_conjugation"]="${MODEL_ROOT}/Wikipedia_normalized_conjugation/phase_2"
  ["chitra_normalized"]="${MODEL_ROOT}/Wikipedia_normalized/phase_2"
)

function set_model_args() {
  MODEL=$1
  DATASET=$2
  MODEL_DIR="${MODEL_DIRS[$1]}"
  DATASET_DIR="${DATASET_ROOT}/${DATASET}"
  OUTPUT_DIR="${OUTPUT_ROOT}/${MODEL}_${DATASET}"
  export MODEL DATASET MODEL_DIR DATASET_DIR OUTPUT_DIR

  # whether if we load the model from pytorch param
  FROM_PT=true
  if [ ${MODEL} = "tohoku" ] ; then
    FROM_PT=false
  fi
  export FROM_PT

  # pretokenizer
  PRETOKENIZER="identity"
  if [ ${MODEL} = "kyoto" ] ; then
    PRETOKENIZER="juman"
  elif [ ${MODEL} = "nict" ] ; then
    PRETOKENIZER="mecab-juman"
  fi
  export PRETOKENIZER

  # tokenizer (sudachi)
  TOKENIZER=${MODEL_DIR}
  if [ ${MODEL:0:6} = "chitra" ] ; then
    TOKENIZER="sudachi"
    WORD_TYPE=${MODEL:7}
    UNIT_TYPE="C"
    SUDACHI_VOCAB="${MODEL_DIR}/vocab.txt"
  else
    # put non-null dummy string (will be ignored)
    WORD_TYPE="none"
    UNIT_TYPE="none"
    SUDACHI_VOCAB="none"
  fi
  export TOKENIZER WORD_TYPE UNIT_TYPE SUDACHI_VOCAB
}

command_echo='( echo \
  "${MODEL}, ${DATASET}, ${MODEL_DIR}, ${DATASET_DIR}, ${OUTPUT_DIR}, " \
  "${FROM_PT}, ${PRETOKENIZER}, "${TOKENIZER}, ${WORD_TYPE}, ${UNIT_TYPE}, ${SUDACHI_VOCAB}, " \
  "${BATCH}, ${LR}, ${EPOCH}, " \
)'

command_run='( \
  python ${SCRIPT_DIR}/run_evaluation.py \
    --model_name_or_path          ${MODEL} \
    --from_pt                     ${FROM_PT} \
    --pretokenizer_name           ${PRETOKENIZER} \
    --tokenizer_name              ${TOKENIZER} \
    --word_form_type              ${WORD_TYPE} \
    --split_unit_type             ${UNIT_TYPE} \
    --sudachi_vocab_file          ${SUDACHI_VOCAB} \
    --dataset_name                ${DATASET} \
    --dataset_dir                 ${DATASET_DIR} \
    --output_dir                  ${OUTPUT_DIR} \
    --do_train                    \
    --do_eval                     \
    --do_predict                  \
    --per_device_eval_batch_size  64 \
    --per_device_train_batch_size ${BATCH} \
    --learning_rate               ${LR} \
    --num_train_epochs            ${EPOCH} \
    # --max_train_samples           100 \
    # --max_val_samples             100 \
    # --max_test_samples            100 \
)'

# mkdir for log
mkdir -p logs
/bin/true > logs/jobs.txt

for MODEL in ${MODEL_NAMES[@]}; do
  for BATCH in ${BATCHES[@]}; do
    for LR in ${LRS[@]}; do
      for EPOCH in ${EPOCHS[@]}; do
        # remove huggingface datasets cache file
        rm $HOME/.cache/huggingface/datasets/ -rf

        export MODEL BATCH LR EPOCH
        set_model_args ${MODEL} ${DATASET}

        script -c "${command_echo}"
        script -c "${command_run}" logs/${MODEL}_batch${BATCH}_lr${LR}_epochs${EPOCH}.log
    done
  done
done
