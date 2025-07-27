# Unity Asset Extractor

This tool allows you to extract assets (Texture2D, TextAsset) from Unity Asset Bundles with ease. It supports both a Graphical User Interface (GUI) for simple usage and a Command Line Interface (CLI) for advanced scripting.

## Features

- **GUI Mode**: User-friendly interface to select source/output folders, CPU usage, and asset types.
- **CLI Mode**: Command-line arguments for automated extraction.
- **Multi-process Support**: Leverages multiple CPU cores for faster extraction.
- **Real-time Progress Bar**: Displays extraction progress with a clear progress bar and live updates for saved files.
- **Load Balancing**: Optimizes task distribution across CPU cores to handle varying bundle sizes efficiently.

## Requirements

- `Python 3.7+`
- `UnityPy==1.23.0`
- `rich`
- `tkinter` (usually bundled with Python)

You can install the required Python packages using pip:

```bash
pip install UnityPy==1.23.0 rich
```

## How to Use

### 1. GUI Mode (Graphical User Interface)

Double click `assest_extracter.py` or Run the script without any command-line arguments to launch the GUI:

```bash
python assest_extracter.py
```

In the GUI:
- **Source Folder**: Click "Browse" to select the directory containing your `.bundle` files.
- **Output Folder**: Click "Browse" to select the directory where you want to save the extracted assets.
- **CPU Usage (%)**: Choose the percentage of your CPU cores to utilize for extraction (25%, 50%, 75%, or 100%).
- **Extract Types**: Select the types of assets you wish to extract (e.g., `Texture2D`, `TextAsset`).
- Click "Start" to begin the extraction process. The GUI will close, and the process will run in your console/terminal.

### 2. CLI Mode (Command Line Interface)

You can use the following command-line arguments for automated extraction:

```bash
python assest_extracter.py -s <source_path> -o <output_path> [-c <cpu_percent>] [-t <type1> <type2> ...]
```

**Arguments:**

- `-s`, `--source`: **Required**. Path to the source directory containing `.bundle` files.
- `-o`, `--output`: **Required**. Path to the output directory where extracted assets will be saved.
- `-c`, `--cpu`: **Optional**. Percentage of CPU to use. Valid options: `25`, `50`, `75`, `100`. Default is `100`.
- `-t`, `--type`: **Optional**. Space-separated list of file types to extract. Valid options: `Texture2D`, `TextAsset`. If not specified, all default types will be extracted.

**Examples:**

Extract all supported types from `./AssetBundles/` to `./Extracted/` using 75% of CPU:
```bash
python assest_extracter.py -s "./AssetBundles/" -o "./Extracted/" -c 75
```

Extract only `Texture2D` assets from `/path/to/bundles/` to `/path/to/output/` using default CPU (100%):
```bash
python assest_extracter.py --source "/path/to/bundles/" --output "/path/to/output/" -t Texture2D
```

Extract both `Texture2D` and `TextAsset` using 50% CPU:
```bash
python assest_extracter.py -s "D:/MyGame/Bundles" -o "D:/MyGame/Extracted" -c 50 -t Texture2D TextAsset
``` 
