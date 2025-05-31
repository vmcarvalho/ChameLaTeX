#!/bin/bash
set -euo pipefail

readonly BUILD_CONFIGS=(
  # "{branch} {output_file.pdf} {flag1} {flag2}"
  "main JohnDoe_CV.pdf"
  "main public/JohnDoe_CV.pdf public"
  "main frontend/JohnDoe_CV.pdf frontend"
  "main public/JohnDoe_CV_frontend.pdf frontend public"
  "acmecorp acmecorp/JohnDoe_CV.pdf frontend"
  # Add your new configuration here
)

readonly BUILD_PREFIX="output_"
readonly SYMLINK_NAME="output"

# === FUNCTIONS ===

# Clean all outputs and temp files
clean() {
  echo "Cleaning build artifacts..."
  rm -rf "$SYMLINK_NAME"
  cleanup_temp_files "."
  echo "Done."
}

# Clean temporary LaTeX files
cleanup_temp_files() {
  local dir="${1:-.}"
  rm -f "$dir"/*.aux "$dir"/*.log "$dir"/*.out "$dir"/*.toc "$dir"/flags.tex #2>/dev/null || true
  git worktree prune
  # Clean up any existing build temp dirs
  find . -maxdepth 1 -type d -name '.build_tmp_*' -exec sh -c 'git worktree remove --force "$1" & rm -rf "$1"' sh {} \;
}

# Show help
help_msg() {
  cat << EOF
Usage: ./build.sh [build|clean|help]

  build     Build all versions (default)
  clean     Remove all outputs and temp files  
  help      Show this help message
EOF
}

# Generate flags.tex file
generate_flags() {
  local branch="$1"
  shift
  
  echo "% Auto-generated flags" > flags.tex
  
  # Add flags for each argument passed
  if [[ $# -gt 0 ]]; then
    for flag in "$@"; do
      # Properly escape backslashes for LaTeX
      echo "\\${flag}true" >> flags.tex
    done
  else
    echo "% No flags enabled" >> flags.tex
  fi
}

# Get current git branch
get_current_branch() {
  git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main"
}

# Core build logic - shared between current branch and worktree builds
do_pdf_build() {
  local target_pdf="$1"
  local branch="$2"
  shift 2

  cleanup_temp_files "."
  
  # Handle case where no flags are provided
  if [[ $# -gt 0 ]]; then
    generate_flags "$branch" "$@"
  else
    generate_flags "$branch"
  fi
  
  echo "  Generated flags:"
  cat flags.tex || true
  
  echo "  Running pdflatex..."
  if pdflatex -interaction=nonstopmode main.tex ; then
    if [[ -f main.pdf ]]; then
      echo "  Moving main.pdf to $target_pdf"
      mv main.pdf "$target_pdf"
      echo "  ✓ Success: $(basename "$target_pdf")"
      cleanup_temp_files "."
      return 0
    else
      echo "  ✗ Error: main.pdf was not generated"
      cleanup_temp_files "."
      return 1
    fi
  else
    echo "  ✗ Error: pdflatex failed"
    [[ -f main.log ]] && echo "  Last few lines of main.log:" && tail -5 main.log
    return 1
  fi
}

# Build a single PDF version
build_version() {
  local branch="$1"
  local target_pdf="$2"
  shift 2
  
  echo "Building: $(basename "$target_pdf") from branch '$branch'"
  
  local output_dir
  output_dir=$(dirname "$target_pdf")
  mkdir -p "$output_dir"
  
  local current_branch
  current_branch=$(get_current_branch)
  
  # Check if we need to switch branches
  if [[ "$branch" == "$current_branch" ]]; then
    # Build from current branch
    echo "  Using current branch: $current_branch"
    if [[ $# -gt 0 ]]; then
      do_pdf_build "$target_pdf" "$branch" "$@"
    else
      do_pdf_build "$target_pdf" "$branch"
    fi
  else
    # Build from specific branch using worktree
    echo "  Switching to branch: $branch"
    local tmpdir=".build_tmp_$branch"

    # Clean up any existing temp worktree
    git worktree prune
    git worktree remove --force "$tmpdir" || rm -rf "$tmpdir"
    # Clean up any existing build temp dirs
    find . -maxdepth 1 -type d -name '.build_tmp_*' -exec sh -c 'git worktree remove --force "$1" & rm -rf "$1"' sh {} \;
    if git worktree add --quiet "$tmpdir" "$branch"; then
      (
        cd "$tmpdir" || exit 1
        echo "  Working in temporary directory: $tmpdir"
        if [[ $# -gt 0 ]]; then
          do_pdf_build "../$target_pdf" "$branch" "$@"
        else
          do_pdf_build "../$target_pdf" "$branch"
        fi
      )
      local build_result=$?
      
      # Clean up worktree
      git worktree remove --force "$tmpdir" 2>/dev/null || rm -rf "$tmpdir"
      return $build_result
    else
      echo "  ✗ Error: Could not create worktree for branch '$branch'"
      echo "  Skipping configuration "
      rm -d "$output_dir"
    fi
  fi
}

# Create timestamped build directory and symlink
setup_build_dir() {
  local timestamp
  timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
  local build_dir="${BUILD_PREFIX}${timestamp}"
  
  echo "Creating build folder: $build_dir" >&2
  mkdir -p "$build_dir"
  
  # Create or update symlink
  rm -f "$SYMLINK_NAME"
  ln -s "$build_dir" "$SYMLINK_NAME"
  
  printf "%s" "$build_dir"
}

# Main build logic using the config array
build() {
  local build_dir
  build_dir=$(setup_build_dir)
  
  echo "Current branch: $(get_current_branch)"
  echo "Building all PDF variants..."
  
  # Process each build configuration
  local config
  for config in "${BUILD_CONFIGS[@]}"; do
    # Parse the configuration string
    read -ra parts <<< "$config"
    local branch="${parts[0]}"
    local target="${parts[1]}"
    local flags=("${parts[@]:2}")  # Remaining elements as flags
    
    echo "Processing config: $config"
    # Handle case where no flags are provided
    if [[ ${#flags[@]} -eq 0 ]]; then
      build_version "$branch" "$build_dir/$target"
    else
      build_version "$branch" "$build_dir/$target" "${flags[@]}"
    fi
  done
  
  # Final cleanup
  cleanup_temp_files "."
  echo "Build complete: $build_dir"
  echo "Symlink created: $SYMLINK_NAME -> $build_dir"
}

# === MAIN ===

case "${1:-build}" in
  build) build ;;
  clean) clean ;;
  help) help_msg ;;
  *) 
    echo "Error: Unknown target '$1'" >&2
    help_msg
    exit 1
    ;;
esac