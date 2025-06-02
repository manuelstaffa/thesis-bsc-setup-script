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

# --- Dependency checks
echo
echo "++++++++++Prerequisites++++++++++"

# sudo dnf install python3-devel
echo "Checking dependencies..."
for dep in git python; do
    if ! command -v $dep &> /dev/null; then
        echo "Error: $dep is not installed or not in PATH."
        exit 1
    fi
done
echo "All required dependencies are present."

# --- Configuration prompts
echo
echo "++++++++++Project Path Configuration++++++++++"

read -p "Enter directory to initialize projects (default: current directory ['$(basename "$PWD")' at path '$(realpath "$PWD")']): " BASE_DIR
BASE_DIR=${BASE_DIR:-$(pwd)}

# --- Clean directory before continuing
SCRIPT_PATH="$(realpath "$0")"
LOGFILE="$BASE_DIR/setup.log"

FILES_TO_DELETE=()
for item in "$BASE_DIR"/* "$BASE_DIR"/.*; do
    [ "$item" = "$BASE_DIR/." ] || [ "$item" = "$BASE_DIR/.." ] && continue
    [ "$(realpath "$item")" = "$SCRIPT_PATH" ] && continue
    [ "$(realpath "$item")" = "$LOGFILE" ] && continue
    FILES_TO_DELETE+=("$item")
done

if [ "${#FILES_TO_DELETE[@]}" -gt 0 ]; then
    echo
    echo "++++++++++Directory Cleanup++++++++++"

    echo "Directory '$BASE_DIR' is not empty."
    if ask_no_default "Delete all contents of '$BASE_DIR' except this script?"; then
        for item in "${FILES_TO_DELETE[@]}"; do
            rm -rf "$item"
        done
        echo "Directory cleared."
    else
        echo "Aborting setup to avoid overwriting files."
        exit 1
    fi
fi

echo
echo "++++++++++Virtual Environemnt Configuration++++++++++"

read -p "Use Conda or venv for environment management? (conda/venv, default: conda): " ENV_TOOL
ENV_TOOL=${ENV_TOOL:-conda}
ENV_TOOL=$(echo "$ENV_TOOL" | tr '[:upper:]' '[:lower:]')

if [ "$ENV_TOOL" = "conda" ]; then
    if ! command -v conda &> /dev/null; then
        echo "Error: Conda not found. Please install it or choose venv."
        exit 1
    fi
    read -p "Enter Python version (default: 3.10): " PYVER
    PYVER=${PYVER:-3.10}
    read -p "Enter Conda environment name (default: myenv): " ENV_NAME
    ENV_NAME=${ENV_NAME:-myenv}
elif [ "$ENV_TOOL" = "venv" ]; then
    read -p "Enter venv directory name (default: .venv): " VENV_DIR
    VENV_DIR=${VENV_DIR:-.venv}
else
    echo "Invalid environment tool selection."
    exit 1
fi

echo
echo "++++++++++Component Configuartion++++++++++"

ask_yes_default "Install ale_py, gymnasium[atari], AutoROM?" && DO_ATARI_PKGS=true || DO_ATARI_PKGS=false
ask_yes_default "Install HackAtari?" && DO_HACKATARI=true || DO_HACKATARI=false
ask_yes_default "Install OC_Atari?" && DO_OCATARI=true || DO_OCATARI=false
ask_yes_default "Install oc_cleanrl?" && DO_OCCLEANRL=true || DO_OCCLEANRL=false
ask_no_default "Install PyTorch with ROCm (AMD GPU support)?" && USE_ROCM=true || USE_ROCM=false

echo
echo "++++++++++Starting setup++++++++++"

mkdir -p "$BASE_DIR"
cd "$BASE_DIR" || exit

# --- Environment setup
if [ "$ENV_TOOL" = "conda" ]; then
    if conda env list | grep -w "$ENV_NAME" &> /dev/null; then
        echo "Conda environment '$ENV_NAME' already exists."
        if ask_no_default "Delete and recreate it?"; then
            conda remove -n "$ENV_NAME" --all -y
        else
            echo "Aborting."
            exit 1
        fi
    fi
    conda create -n "$ENV_NAME" python="$PYVER" -y
    PIP="conda run -n $ENV_NAME pip"
    PYTHON="conda run -n $ENV_NAME python"
elif [ "$ENV_TOOL" = "venv" ]; then
    if [ -d "$BASE_DIR/$VENV_DIR" ]; then
        echo "Venv '$VENV_DIR' already exists."
        if ask_no_default "Delete and recreate it?"; then
            rm -rf "$BASE_DIR/$VENV_DIR"
        else
            echo "Aborting."
            exit 1
        fi
    fi
    python -m venv "$BASE_DIR/$VENV_DIR"
    source "$BASE_DIR/$VENV_DIR/bin/activate"
    PIP="pip"
    PYTHON="python"
fi

# --- Install base packages
if [ "$DO_ATARI_PKGS" = true ]; then
    #AUTOROM="$BASE_DIR/$VENV_DIR/bin/AutoROM"
    $PIP install ale_py "gymnasium[atari]"
    $PIP install AutoROM
    #$AUTOROM --accept-license
fi

# --- HackAtari
if [ "$DO_HACKATARI" = true ]; then
    clone_repo "git@github.com:k4ntz/HackAtari.git" "https://github.com/k4ntz/HackAtari.git" "HackAtari"
    cd HackAtari
    $PIP install -e .
    cd ..
fi

# --- OC_Atari
if [ "$DO_OCATARI" = true ]; then
    clone_repo "git@github.com:k4ntz/OC_Atari.git" "https://github.com/k4ntz/OC_Atari.git" "OC_Atari"
    cd OC_Atari
    $PIP install -e .
    $PIP install -r requirements.txt
    cd ..
fi

# --- oc_cleanrl
if [ "$DO_OCCLEANRL" = true ]; then
    clone_repo "git@github.com:BluemlJ/oc_cleanrl.git" "https://github.com/BluemlJ/oc_cleanrl.git" "oc_cleanrl"
    cd oc_cleanrl
    $PIP install -r requirements/requirements.txt
    $PIP install -r requirements/requirements-atari.txt
    cd ..
fi

# --- ROCm
if [ "$USE_ROCM" = true ]; then
    $PIP install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/rocm6.3
fi

# --- Symlink submodules
mkdir -p "$BASE_DIR/oc_cleanrl/submodules"
ln -sfn "$BASE_DIR/OC_Atari" "$BASE_DIR/oc_cleanrl/submodules/OC_Atari"
ln -sfn "$BASE_DIR/HackAtari" "$BASE_DIR/oc_cleanrl/submodules/HackAtari"

# --- AutoROM
if [ "$DO_ATARI_PKGS" = true ]; then
    if [ "$ENV_TOOL" = "conda" ]; then
        conda run -n "$ENV_NAME" AutoROM --accept-license
    else
        source "$VENV_DIR/bin/activate"
        AutoROM --accept-license
        deactivate
    fi
fi

# --- README
echo
echo "++++++++++Creating README++++++++++"

README_PATH="$BASE_DIR/README.md"
echo "# Setup Summary & Useful Commands" > "$README_PATH"
echo "" >> "$README_PATH"

if [ "$ENV_TOOL" = "conda" ]; then
echo "## Conda" >> "$README_PATH"
echo "\`\`\`bash" >> "$README_PATH"
echo "conda activate $ENV_NAME" >> "$README_PATH"
echo "conda deactivate" >> "$README_PATH"
echo >> "$README_PATH"
echo "conda env remove --name $ENV_NAME" >> "$README_PATH"
echo "\`\`\`" >> "$README_PATH"
elif [ "$ENV_TOOL" = "venv" ]; then
echo "## venv" >> "$README_PATH"
echo "\`\`\`bash" >> "$README_PATH"
echo "source $VENV_DIR/bin/activate" >> "$README_PATH"
echo "deactivate" >> "$README_PATH"
echo "\`\`\`" >> "$README_PATH"
fi

echo "" >> "$README_PATH"
echo "## HackAtari" >> "$README_PATH"
echo "\`\`\`bash" >> "$README_PATH"
echo "cd HackAtari/scripts" >> "$README_PATH"
echo "python run.py -g Freeway" >> "$README_PATH"
echo "\`\`\`" >> "$README_PATH"

echo "## ALE & Gymnasium Test" >> "$README_PATH"
echo "\`\`\`bash" >> "$README_PATH"
echo "python -m ale_py.example" >> "$README_PATH"
echo "python -c \"import gymnasium; print(gymnasium.make('ALE/Freeway-v5'))\"" >> "$README_PATH"
echo "\`\`\`" >> "$README_PATH"

if [ "$USE_ROCM" = true ]; then
echo "## ROCm Torch Test" >> "$README_PATH"
echo "\`\`\`bash" >> "$README_PATH"
echo "python -c \"import torch; print(torch.version.__version__, torch.cuda.is_available())\"" >> "$README_PATH"
echo "\`\`\`" >> "$README_PATH"
fi

echo "Setup complete. Logs saved to: $LOG_FILE"

# --- Completion
echo
echo "++++++++++Setup complete++++++++++"

echo "Logs saved to: $LOG_FILE"
echo

if [ "$ENV_TOOL" = "conda" ]; then
echo "To activate this environment, use:"
echo
echo "  $ conda activate $ENV_NAME"
echo
echo "To deactivate an active environment, use"
echo
echo "  $ conda deactivate"
elif [ "$ENV_TOOL" = "venv" ]; then
echo "To activate this environment, use:"
echo
echo "  source \"$VENV_DIR/bin/activate\""
echo
echo "To deactivate an active environment, use:"
echo
echo "  deactivate"
fi
