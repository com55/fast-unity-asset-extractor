import os
import UnityPy
from UnityPy.classes import TextAsset, Texture2D
import concurrent.futures
import multiprocessing
from rich.console import Console
import tkinter as tk
from tkinter import filedialog, messagebox, ttk
import argparse
import sys
import threading
from rich.progress import Progress, BarColumn, TextColumn, TimeElapsedColumn, TimeRemainingColumn

console = Console()

DEFAULT_TYPES = [
    "Texture2D",
    "TextAsset"
]

def process_bundle(full_path_output_types_queue):
    full_path, output_path, selected_types, event_queue = full_path_output_types_queue
    try:
        env = UnityPy.load(full_path)
        for obj in env.objects:
            if obj.type.name not in selected_types:
                continue

            container: str = obj.container
            if not container:
                continue

            parts = container.split("/")
            filename = parts[-1]
            if filename.count(".") >= 2:
                filename = ".".join(filename.split(".")[:-1])

            save_dir = os.path.join(output_path, *parts[:-1])
            os.makedirs(save_dir, exist_ok=True)
            save_path = os.path.join(save_dir, filename)

            data = obj.read()
            if isinstance(data, TextAsset):
                with open(save_path, "wb") as f:
                    f.write(data.m_Script.encode("utf-8", errors="surrogateescape"))
                    event_queue.put(("saved_item", "text", filename, save_path))
            elif isinstance(data, Texture2D) and container.endswith(".png"):
                data.image.save(save_path)
                event_queue.put(("saved_item", "texture", filename, save_path))
    except Exception as e:
        event_queue.put(("error", full_path, str(e)))

    event_queue.put(("bundle_completed", full_path))

def remove_empty_dirs(path):
    for root, dirs, _ in os.walk(path, topdown=False):
        for d in dirs:
            dir_path = os.path.join(root, d)
            if not os.listdir(dir_path):
                os.rmdir(dir_path)

def print_consumer(event_queue: multiprocessing.Queue, total_bundles: int, stop_event: threading.Event, progress: Progress, main_task_id, output_path: str):
    while True:
        if not event_queue.empty():
            event = event_queue.get()
            event_type = event[0]

            if event_type == "saved_item":
                item_type, filename, save_path = event[1], event[2], event[3]
                color = "yellow" if item_type == "text" else "blue"
                # Display path relative to the output folder
                relative_save_path = os.path.relpath(save_path, output_path)
                console.print(f"[dim]Saved [{color}]{filename} [dim]to [reset]{relative_save_path}")
            elif event_type == "error":
                _, path, error_msg = event[1], event[2]
                console.print(f"❌ Error in {os.path.basename(path)}: {error_msg}", style="bold red")
            elif event_type == "bundle_completed":
                progress.update(main_task_id, advance=1)
        elif stop_event.is_set() and event_queue.empty():
            break
        else:
            threading.Event().wait(0.01)


def extract_assets_from_bundles(source_path: str, output_path: str, selected_types: list[str], cpu_percent: int):
    bundle_files = [
        os.path.join(root, f)
        for root, _, files in os.walk(source_path)
        for f in files if f.endswith(".bundle")
    ]

    total_cpu_count = multiprocessing.cpu_count()
    if cpu_percent == 100:
        num_workers = total_cpu_count
    else:
        num_workers = max(1, int(total_cpu_count * (cpu_percent / 100)))

    total_bundles = len(bundle_files)

    manager = multiprocessing.Manager()
    event_queue = manager.Queue()
    stop_event = threading.Event()

    with Progress(
        TextColumn("[progress.description]{task.description}"),
        BarColumn(),
        TextColumn("[progress.percentage]{task.percentage:>5.2f}%"),
        TextColumn("[green]{task.completed}/{task.total}"),
        TimeRemainingColumn(),
        TimeElapsedColumn(),
        console=console,
    ) as progress:
        main_task = progress.add_task("[green]Extracting", total=total_bundles)

        printer_thread = threading.Thread(target=print_consumer, args=(event_queue, total_bundles, stop_event, progress, main_task, output_path))
        printer_thread.start()

        args = [(bf, output_path, selected_types, event_queue) for bf in bundle_files]

        with concurrent.futures.ProcessPoolExecutor(max_workers=num_workers) as executor:
            # Using map with chunksize=1 for better load balancing when task durations vary
            for _ in executor.map(process_bundle, args, chunksize=1):
                pass

        stop_event.set()
        printer_thread.join()

    remove_empty_dirs(output_path)
    console.print("Completed!", style="bold green")
    input("Press any key to exit...")

def create_gui():
    root = tk.Tk()
    root.title("Unity Asset Extractor")

    tk.Label(root, text="Source Folder:").grid(row=0, column=0, padx=5, pady=5, sticky="w")
    source_path_entry = tk.Entry(root, width=50)
    source_path_entry.grid(row=0, column=1, padx=5, pady=5)
    tk.Button(root, text="Browse", command=lambda: source_path_entry.delete(0, tk.END) or source_path_entry.insert(0, filedialog.askdirectory())).grid(row=0, column=2, padx=5, pady=5)

    tk.Label(root, text="Output Folder:").grid(row=1, column=0, padx=5, pady=5, sticky="w")
    output_path_entry = tk.Entry(root, width=50)
    output_path_entry.grid(row=1, column=1, padx=5, pady=5)
    tk.Button(root, text="Browse", command=lambda: output_path_entry.delete(0, tk.END) or output_path_entry.insert(0, filedialog.askdirectory())).grid(row=1, column=2, padx=5, pady=5)

    tk.Label(root, text="CPU Usage (%):").grid(row=2, column=0, padx=5, pady=5, sticky="w")
    cpu_percent_var = tk.IntVar(value=100)
    cpu_options = [25, 50, 75, 100]
    cpu_menu = ttk.Combobox(root, textvariable=cpu_percent_var, values=cpu_options, state="readonly")
    cpu_menu.grid(row=2, column=1, padx=5, pady=5, sticky="ew")
    cpu_menu.set(100)

    tk.Label(root, text="Extract Types:").grid(row=3, column=0, padx=5, pady=5, sticky="nw")
    type_vars = {}
    for i, type_name in enumerate(DEFAULT_TYPES):
        var = tk.BooleanVar(value=True)
        cb = tk.Checkbutton(root, text=type_name, variable=var)
        cb.grid(row=3 + i, column=1, sticky="w", padx=5, pady=2)
        type_vars[type_name] = var

    def start_extraction_gui():
        source_path = source_path_entry.get()
        output_path = output_path_entry.get()
        cpu_percent = cpu_percent_var.get()
        selected_types = [name for name, var in type_vars.items() if var.get()]

        if not source_path or not output_path:
            messagebox.showerror("Error", "Please select both source and output folders.")
            return

        root.destroy() # Close the GUI window before starting extraction

        try:
            extract_assets_from_bundles(source_path, output_path, selected_types, cpu_percent)
        except Exception as e:
            messagebox.showerror("Error", f"An error occurred: {e}")

    extract_button = tk.Button(root, text="Start", command=start_extraction_gui, width=8)
    extract_button.grid(row=3 + len(DEFAULT_TYPES), column=0, columnspan=3, pady=10)

    # Center the window
    root.update_idletasks()
    width = root.winfo_width()
    height = root.winfo_height()
    x = (root.winfo_screenwidth() // 2) - (width // 2)
    y = (root.winfo_screenheight() // 2) - (height // 2)
    root.geometry(f'{width}x{height}+{x}+{y}')

    root.mainloop()

def main():
    parser = argparse.ArgumentParser(description="Unity Asset Extractor")
    parser.add_argument("-s", "--source", help="Path to source directory containing .bundle files")
    parser.add_argument("-o", "--output", help="Path to output directory for extracted assets")
    parser.add_argument("-c", "--cpu", type=int, choices=[25, 50, 75, 100], default=100,
                        help="Percentage of CPU to use (25, 50, 75, 100)")
    parser.add_argument("-t", "--type", nargs='*', choices=[t.lower() for t in DEFAULT_TYPES],
                        help=f"File types to extract (e.g., {' '.join([t.lower() for t in DEFAULT_TYPES])})")

    args = parser.parse_args()

    is_cli_mode = any(arg in sys.argv for arg in ["-s", "--source", "-o", "--output"])

    if is_cli_mode:
        if not args.source or not args.output:
            console.print("[bold red]Error: In CLI mode, --source and --output are required.[/bold red]")
            parser.print_help()
            sys.exit(1)
        selected_types = [t.capitalize() for t in args.type] if args.type else DEFAULT_TYPES
        console.print(f"CLI Mode: Source='{args.source}', Output='{args.output}', CPU={args.cpu}%, Types={selected_types}")
        extract_assets_from_bundles(args.source, args.output, selected_types, args.cpu)
    else:
        create_gui()

if __name__ == "__main__":
    multiprocessing.freeze_support()
    main()