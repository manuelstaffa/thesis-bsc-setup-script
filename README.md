# Automatic Bash Setup Script 'LLM-assisted Reward Shaping in Object-centric Environments'

Automatic modular setup script for the thesis project 'LLM-assisted Reward Shaping in Object-centric Environments'

Features
----
1. Automatic dependency check & installation
2. Choose an install location and automatically clear target folder
3. Choose between conda or .venv, including the option to replace existing environments
4. Choose different modules (gymnasium+AutoROM+ale_py, HackAtari, OC_Atari, oc_cleanrl, PyTorch ROCm (AMD GPU support)) to install
5. Git SSH installation with automatic HTTPS fallback
6. README.md creation containing some useful commands
7. Log file for installation process

Requirements
---
1. Python
2. Git (preferably with SSH sign-in)
3. Conda (when using conda)
4. python3-devel (when using .venv)

How To Use
---
1. Place script in target folder (or any other folder)
2. Run ```bash path/to/setup.sh```
3. Follow the on-screen prompts
