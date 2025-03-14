#!/bin/bash
#ddev-generated

# ANSI color codes
brown='\033[0;33m'
NC='\033[0m' # No Color

show_logo() {
  # ASCII art with brown color
  echo ""
  echo ""
  echo -e "${brown}"
  cat << EOF
  ___  _ _ _ _
 / _ \| (_|_) |
/ /_\ \ |_ _| |__   ___
|  _  | | | | '_ \ / _ \\
| | | | | | | |_) |  __/
\_| |_/_| |_|_.__/ \___|
       _/ |
      |__/
             by Metadrop
EOF
  echo -e "${NC}" # Reset color
  echo ""
}
