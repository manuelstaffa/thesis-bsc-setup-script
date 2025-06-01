#!/bin/bash

set -e

LOG_FILE="setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# --- Prompt helpers
ask_yes_default() {
    while true; do
        read -p "$1 [Y/n]: " yn
        case "$yn" in
            [Yy]* | "" ) return 0 ;;
            [Nn]* ) return 1 ;;
            * ) echo "Please answer y or n." ;;
        esac
    done
}

ask_no_default() {
    while true; do
        read -p "$1 [y/N]: " yn
        case "$yn" in
            [Yy]* ) return 0 ;;
            [Nn]* | "" ) return 1 ;;
            * ) echo "Please answer y or n." ;;
        esac
    done
}

clone_repo() {
    local SSH_URL=$1
    local HTTPS_URL=$2
    local DIR=$3
    if git clone "$SSH_URL" "$DIR"; then
        echo "Cloned $DIR via SSH."
    else
        echo "SSH clone failed. Trying HTTPS..."
        git clone "$HTTPS_URL" "$DIR"
        echo "Cloned $DIR via HTTPS."
    fi
}

# --- 0. Dependency checks
echo
echo "++++++++++Prerequisites++++++++++"
echo "Checking dependencies..."
for dep in git conda python; do
    if ! command -v $dep &> /dev/null; then
        echo "❌ Error: $dep is not installed or not in PATH."
        exit 1
    fi
done
echo "All required dependencies are present."

# --- 0. Configuration prompts
echo
echo "++++++++++Setup Configuration++++++++++"

read -p "Enter directory to initialize projects (default: current dir): " BASE_DIR
BASE_DIR=${BASE_DIR:-$(pwd)}

if ask_yes_default "Create a new Conda environment?"; then
    read -p "Enter Python version (default: 3.10): " PYVER
    PYVER=${PYVER:-3.10}
    read -p "Enter environment name (default: myenv): " ENV_NAME
    ENV_NAME=${ENV_NAME:-myenv}
    CREATE_ENV=true
else
    CREATE_ENV=false
fi

ask_yes_default "Install ale_py, gymnasium[atari], AutoROM?" && DO_ATARI_PKGS=true || DO_ATARI_PKGS=false
ask_yes_default "Install HackAtari?" && DO_HACKATARI=true || DO_HACKATARI=false
ask_yes_default "Install OC_Atari?" && DO_OCATARI=true || DO_OCATARI=false
ask_yes_default "Install oc_cleanrl?" && DO_OCCLEANRL=true || DO_OCCLEANRL=false
ask_no_default "Install PyTorch with ROCm (AMD GPU support)?" && USE_ROCM=true || USE_ROCM=false

echo
echo "++++++++++Starting setup++++++++++"
mkdir -p "$BASE_DIR"
cd "$BASE_DIR" || exit

# --- 1. Check directory cleanliness
if [ "$(ls -A "$BASE_DIR")" ]; then
    echo "Directory '$BASE_DIR' is not empty."
    if ask_no_default "Delete all contents of '$BASE_DIR' except this script, README.md, and log file?"; then
        SCRIPT_PATH="$(realpath "$0")"
        LOGFILE="$BASE_DIR/setup.log"
        README="$BASE_DIR/README.md"

        for item in "$BASE_DIR"/* "$BASE_DIR"/.*; do
            # Skip . and ..
            [ "$item" = "$BASE_DIR/." ] || [ "$item" = "$BASE_DIR/.." ] && continue

            # Skip script itself
            [ "$(realpath "$item")" = "$SCRIPT_PATH" ] && continue

            # Skip README.md
            [ "$item" = "$README" ] && continue

            # Skip log file
            [ "$item" = "$LOGFILE" ] && continue

            rm -rf "$item"
        done
        echo "Directory cleared (script, README.md, and log file preserved)."
    else
        echo "Aborting setup to avoid overwriting existing files."
        exit 1
    fi
fi

# --- 2. Conda env
if [ "$CREATE_ENV" = true ]; then
    if conda env list | grep -w "$ENV_NAME" &> /dev/null; then
        echo "A Conda environment named \"$ENV_NAME\" already exists."
        if ask_no_default "Delete and recreate it?"; then
            conda remove -n "$ENV_NAME" --all -y
            echo "Deleted existing environment."
        else
            echo "Setup aborted. Please use a different environment name."
            exit 1
        fi
    fi
    echo "Creating environment '$ENV_NAME' with Python $PYVER..."
    conda create -n "$ENV_NAME" python="$PYVER" -y
fi

# --- 3. Atari packages
if [ "$DO_ATARI_PKGS" = true ]; then
    echo "Installing ale_py, gymnasium[atari], AutoROM..."
    conda run -n "$ENV_NAME" pip install ale_py
    conda run -n "$ENV_NAME" pip install "gymnasium[atari]"
    # conda run -n "$ENV_NAME" AutoROM --accept-license
fi

# --- 4. HackAtari
if [ "$DO_HACKATARI" = true ]; then
    echo "Cloning & installing HackAtari..."
    clone_repo "git@github.com:k4ntz/HackAtari.git" "https://github.com/k4ntz/HackAtari.git" "HackAtari"
    cd HackAtari || exit
    conda run -n "$ENV_NAME" pip install -e .
    cd ..
fi

# --- 5. OC_Atari
if [ "$DO_OCATARI" = true ]; then
    echo "Cloning & installing OC_Atari..."
    clone_repo "git@github.com:k4ntz/OC_Atari.git" "https://github.com/k4ntz/OC_Atari.git" "OC_Atari"
    cd OC_Atari || exit
    conda run -n "$ENV_NAME" pip install -e .
    conda run -n "$ENV_NAME" pip install -r requirements.txt
    cd ..
fi

# --- 6. oc_cleanrl
if [ "$DO_OCCLEANRL" = true ]; then
    echo "Cloning & installing oc_cleanrl..."
    clone_repo "git@github.com:BluemlJ/oc_cleanrl.git" "https://github.com/BluemlJ/oc_cleanrl.git" "oc_cleanrl"
    cd oc_cleanrl || exit
    #cd submodules/OC_Atari || exit
    #conda run -n "$ENV_NAME" pip install -e .
    #cd ../..
    conda run -n "$ENV_NAME" pip install -r requirements/requirements.txt
    conda run -n "$ENV_NAME" pip install -r requirements/requirements-atari.txt
    cd ..
fi

# --- 7. AMD GPU ROCm support
if [ "$USE_ROCM" = true ]; then
    #echo "Reading torch version from oc_cleanrl/requirements/requirements.txt..."
    #TORCH_VER=$(grep -E "^torch==[0-9]+\.[0-9]+\.[0-9]+" "$BASE_DIR/oc_cleanrl/requirements/requirements.txt" | head -n 1 | cut -d'=' -f3)
    #if [ -z "$TORCH_VER" ]; then
    #    echo "Could not find torch version in requirements file. Aborting ROCm installation."
    #    exit 1
    #fi
    #echo "Installing torch==$TORCH_VER with ROCm..."
    #conda run -n "$ENV_NAME" pip install "torch==$TORCH_VER+rocm5.6" "torchvision==0.16.2+rocm5.6" "torchaudio==$TORCH_VER" --index-url https://download.pytorch.org/whl/rocm5.6
    echo "Installing torch with ROCm..."
    conda run -n "$ENV_NAME" pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/rocm6.3
fi

# --- 8. Link OC_Atari and HackAtari into oc_cleanrl/submodules
echo "Creating hard links to OC_Atari and HackAtari in oc_cleanrl/submodules..."
mkdir -p "$BASE_DIR/oc_cleanrl/submodules"

ln -sfn "$BASE_DIR/OC_Atari" "$BASE_DIR/oc_cleanrl/submodules/OC_Atari"
ln -sfn "$BASE_DIR/HackAtari" "$BASE_DIR/oc_cleanrl/submodules/HackAtari"

# --- 8. Atutorom accept
if [ "$DO_ATARI_PKGS" = true ]; then
    echo "Accepting AutoROM license..."
    conda run -n "$ENV_NAME" AutoROM --accept-license
fi

# --- Readme
echo
echo "++++++++++Creating README++++++++++"
README_PATH="$BASE_DIR/README.md"

echo "# Setup Summary & Useful Commands" > "$README_PATH"
echo "" >> "$README_PATH"

# Conda usage
echo "## Conda" >> "$README_PATH"
echo "\`\`\`bash" >> "$README_PATH"
echo "conda activate $ENV_NAME" >> "$README_PATH"
echo "conda deactivate" >> "$README_PATH"
echo "\`\`\`" >> "$README_PATH"
echo "" >> "$README_PATH"

# HackAtari usage
if [ "$DO_HACKATARI" = true ]; then
echo "## HackAtari" >> "$README_PATH"
echo "\`\`\`bash" >> "$README_PATH"
echo "cd \$BASE_DIR/HackAtari/scripts" >> "$README_PATH"
echo "python run.py -g Freeway -r rewardfunc_path  # or Frostbite, Alien, etc." >> "$README_PATH"
echo "\`\`\`" >> "$README_PATH"
echo "" >> "$README_PATH"
fi

# OC_Atari usage
#if [ "$DO_OCATARI" = true ]; then
#echo "## OC_Atari (manual testing)" >> "$README_PATH"
#echo "\`\`\`bash" >> "$README_PATH"
#echo "cd \$BASE_DIR/OC_Atari" >> "$README_PATH"
#echo "python -m ocatari.play" >> "$README_PATH"
#echo "\`\`\`" >> "$README_PATH"
#echo "" >> "$README_PATH"
#fi

# oc_cleanrl usage
#if [ "$DO_CLEANRL" = true ]; then
#echo "## OC_CleanRL (RL training/evaluation)" >> "$README_PATH"
#echo "\`\`\`bash" >> "$README_PATH"
#echo "cd \$BASE_DIR/oc_cleanrl" >> "$README_PATH"
#echo "python train.py --env-id ALE/Freeway-v5" >> "$README_PATH"
#echo "\`\`\`" >> "$README_PATH"
#echo "" >> "$README_PATH"
#fi

# ALE/Gymnasium
echo "## ALE & Gymnasium Testing" >> "$README_PATH"
echo "\`\`\`bash" >> "$README_PATH"
echo "python -m ale_py.example" >> "$README_PATH"
echo "python -c \"import gymnasium; print(gymnasium.make('ALE/Freeway-v5'))\"" >> "$README_PATH"
echo "\`\`\`" >> "$README_PATH"
echo "" >> "$README_PATH"

# ROCm if installed
if [ "$USE_ROCM" = true ]; then
echo "## AMD ROCm Torch Check" >> "$README_PATH"
echo "\`\`\`bash" >> "$README_PATH"
echo "python -c \"import torch; print(torch.version.__version__, torch.cuda.is_available())\"" >> "$README_PATH"
echo "\`\`\`" >> "$README_PATH"
echo "" >> "$README_PATH"
fi

echo "✅ README.md created at: $README_PATH"

# --- Completion
echo
echo "++++++++++Setup complete++++++++++"
echo "Logs saved to: $LOG_FILE"
echo
echo "To activate this environment, use:"
echo "  $ conda activate $ENV_NAME"
echo
echo "To deactivate an active environment, use"
echo
echo "  $ conda deactivate"




