# Run lualatex from the QUANTUMCOMPUTING/ root so that ceri/sty/rapport.cls resolves.
# LaTeX Workshop picks this up automatically when the workspace root contains it.
$lualatex = 'lualatex -synctex=1 -interaction=nonstopmode -file-line-error %O %S';
$pdf_mode = 4;   # use lualatex

# Keep aux files next to the source (same folder as the .tex file)
$out_dir = '';
