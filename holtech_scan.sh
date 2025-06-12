#!/bin/bash

# --- Helper Functions ---
verbose_echo() {
    if [[ "$VERBOSE" -eq 1 ]]; then
        echo "["$(date +"%H:%M:%S")"]: $*" # Print all arguments passed to verbose_echo
    fi
}
tstamp_echo() {
    echo "["$(date +"%H:%M:%S")"]: $*"
}

# --- Global Variables ---
VERBOSE=0 # Verbose output is 0 by default
TEST=0 # Test mode is 0 by default
AUTO_FILE_NAMES=0 # Auto generated file names are 0 by default
DEFAULT_DIRECTORY="/home/$USER/Documents/HScan/" # Default directory for saved scans
TARGET_DIRECTORY="${DEFAULT_DIRECTORY}" # Target directory is default unless changed
DIFFERENT_DIRECTORY=0 # Toggle if directory changed with argument
OPEN_FILE=0 # Toggle to open file, 0 by default
PRINT_FILE=0 # Toggle to print file, 0 by default
HELPTEXT="""
    [ARGUMENTS]         [DESCRIPTION]               [DEFAULT]
    -h --help:          Show help menu              False
    -v --verbose:       Enable verbose output       False
    -t --test:          Enable test mode            False
    -a --auto:          Auto generate file names    False
    -d --directory:     Set directory              (${DEFAULT_DIRECTORY})
    -o --open:          Open the file               False
    -p --print:         Print the file              False
"""
PRINTERTEXT="""
    Printer Issues?

    It appears that no default printer is set on this system.
    Use the 'lpoptions' command to set one:
        1. List available printers using 'lpstat -p -d'
        2. Set a default printer using 'lpoptions -d <printer_name>'

    Try again once the issue is resolved.
"""
# --- Argument Handling --- 
# Function argument checks and responses
while [[ "$#" -gt 0 ]]; do # Loop while there are arguments left
    case "$1" in # Check the first argument
        -h|--help)
            tstamp_echo "${HELPTEXT}"
            exit 1
            ;;
        -v|--verbose)
            VERBOSE=1 # Set verbose output to 1
            verbose_echo "Verbose mode (-v) enabled."
            shift # Consume the -v argument
            ;;
        -t|--test)
            TEST=1 # Set test mode to 1
            verbose_echo "Test mode (-t) enabled."
            shift # Consume the -t argument
            ;;
        -a|--auto)
            AUTO_FILE_NAMES=1 # Set test mode to 1
            verbose_echo "Automatic mode (-a) enabled."
            shift # Consume the -a argument
            ;;
        -d|--directory)
            shift # Consume the -d argument
            # Check argument is not another flag
            if [[ -n "$1" && "$1" != -* ]]; then
                TARGET_DIRECTORY="$1"
                verbose_echo "Target directory set to '$TARGET_DIRECTORY'."
                DIFFERENT_DIRECTORY=1
                verbose_echo "Target directory is not default."
                shift # Consume the directory path argument
            else
                tstamp_echo "Error: --directory requires a directory path." >&2
                exit 1
            fi
            ;;
        -o|--open)
            OPEN_FILE=1 # Set open file mode to 1
            verbose_echo "Open file (-o) enabled."
            shift # Consume the -o argument
            ;;
        -p|--print)
            PRINT_FILE=1 # Set print file mode to 1
            verbose_echo "Print file (-p) enabled."
            shift # Consume the -p argument
            ;;
                        
        *)
            tstamp_echo "Error: Unknown argument: $1" >&2 # Report the unknown argument
            exit 1 # Throw error if an unknown argument is provided
            ;;
    esac
done

# --- Input Sanitation ---
fetch_fileext() {
    local filename="$1"
    local extension="${filename##*.}"

    if [[ "$filename" == "$extension" ]]; then
        extension="" # None found
        return 1 # Fail
    elif [[ "$filename" == ".*" && "$filename" != *.* ]]; then # Multiple dot support
        extension=""
        return 1 # Fail
    fi
    echo $extension # Output file extension
    return 0 # Success
}

validate_filename() {
    local proposed_name="$1" # Save user input as proposed name
    local invalid_chars='/\x00' # Store invalid characters (null byte etc.)
    local valid_filetypes=[]

    # Empty input
    if [[ -z "$proposed_name" ]]; then
        tstamp_echo "Error: Filename cannot be empty." >&2
        return 1
    fi

    # Forbidden characters
    if [ -n "$invalid_chars" ] && echo "$proposed_name" | grep -q "[${invalid_chars}]"; then
        tstamp_echo "Error: Filename contains forbidden characters." >&2
        return 1
    fi

    # Hyphens
    if [[ "$proposed_name" == -* ]]; then
        tstamp_echo "Error: Filename cannot start with a hyphen (-)." >&2
        return 1
    fi

    # Reserved names
    if [[ "$proposed_name" == "." || "$proposed_name" == ".." ]]; then
        tstamp_echo "Error: Filename cannot be '.' or '..'." >&2
        return 1
    fi

    # Leading spaces
    if [[ "$proposed_name" =~ ^[[:space:]]|[[[:space:]]]$ ]]; then
        tstamp_echo "Error: Filename cannot start or end with spaces." >&2
        return 1
    fi

    # Fetch file extension
    FILE_EXTENSION=$(fetch_fileext "$proposed_name")
    verbose_echo "Found extension '$FILE_EXTENSION' for '$proposed_name'"

    # File extension checks
    if [[ $FILE_EXTENSION = "" ]]; then
        tstamp_echo "Error: Filename must have an extension"
        return 1
    elif [[ $FILE_EXTENSION != "pdf" ]]; then
        tstamp_echo "Error: File extension is not supported"
        return 1
    fi

    # If all goes well, allocate the proposed name as the valifated file name
    VALIDATED_FILENAME="$proposed_name"
    verbose_echo "Filename '$VALIDATED_FILENAME' is valid."

    return 0 # Success
}

# --- Handlers ---
# File name handling
tstamp_echo "Checking filename..."
# Generate a filename if the -a argument was provided or ask for input
if [[ "$AUTO_FILE_NAMES" -eq 0 ]]; then 
    verbose_echo "Manual filename required."
    FILENAME="" # Initialise filename variable
    while true; do
        read -p "Please enter a filename for the scan (e.g. MyScan.pdf): " fname

        verbose_echo "Validating filename..."
        if validate_filename "$fname"; then
            FILENAME="$VALIDATED_FILENAME" # Store the entered name
            break # exit the loop because a valid input is taken
        fi
    done
else
    # Automatically generate file name using current timestamp
    TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
    verbose_echo "Manual filename not required. Using timestamp: [$TIMESTAMP]."
    FILENAME="$TIMESTAMP.pdf"
    verbose_echo "Filename created: '$FILENAME'"
fi

# --- File Management ---
tstamp_echo "Checking and creating directories..."

# Function to check and ensure a directory exists
check_and_create_directory() {
    local directory_path="$1" # The path to the directory
    local directory_name_for_messages="$2" # Its name (e.g. 'target directory')

    # Attempt to create the directory if it doesn't exist
    mkdir -p "$directory_path"

    # Check if the directory exists after attempt
    if [ ! -d "$directory_path" ]; then
        tstamp_echo "Error: Failed to create or access the ${directory_name_for_messages} at '$directory_path'." >&2
        exit 1
    fi

    verbose_echo "Ensured ${directory_name_for_messages} '${directory_path}' exists."
}

# Create the target directory if it doesn't exist
check_and_create_directory "$TARGET_DIRECTORY" "target directory"

# Generate OUTPUT and TEMP directories using TARGET_DIRECTORY
if [[ ${DIFFERENT_DIRECTORY} -eq 1 ]]; then 
    # Target is different from default
    OUTPUT_DIRECTORY="${TARGET_DIRECTORY}" 
    TEMP_DIRECTORY="${TARGET_DIRECTORY}hscan_temp/"
    verbose_echo "Target: '${TARGET_DIRECTORY}' is different from Default: '${DEFAULT_DIRECTORY}'."
else 
    # Default directories
    OUTPUT_DIRECTORY="${TARGET_DIRECTORY}$(fetch_fileext "${FILENAME}")/"
    TEMP_DIRECTORY="${TARGET_DIRECTORY}hscan_temp/"
    verbose_echo "Target: '${TARGET_DIRECTORY}' is the same as Default: '${DEFAULT_DIRECTORY}'."
fi

# Create the TEMP directory if it doesn't exist
check_and_create_directory "$TEMP_DIRECTORY" "temp directory"
# Create the OUTPUT directory if it doesn't exist
check_and_create_directory "$OUTPUT_DIRECTORY" "output directory"

# --- Scanning ---
# Start scan procedure
if [[ "$TEST" -eq 0 ]]; then
    tstamp_echo "Performing scan..."
    # Tell the printer to perform a scan
    scanimage --format=tiff --mode Gray --resolution 300 > "${TEMP_DIRECTORY}scan_result.tiff"
    STATUS=$?
    # Check status
    if [[ "$STATUS" -eq 0 ]]; then
        tstamp_echo "Scan Successful!"
    else
        tstamp_echo "Scan Unsuccessful."
        
        # Remove temporary files
        verbose_echo "Removing temp files..."
        rm -f "${TEMP_DIRECTORY}scan_result.tiff"
        rm -r "${TEMP_DIRECTORY}"

        exit 1 # CHANGE AT LATER DATE TO CONVERT ERROR INTO RESULT PDF
    fi
    # Convert scan to PDF
    verbose_echo "Converting to PDF..."
    convert "${TEMP_DIRECTORY}scan_result.tiff" "${OUTPUT_DIRECTORY}${FILENAME}"
    PDF_CREATED=1
else
    tstamp_echo "Test mode enabled. Faking scan..."
    
    # In test mode, create a dummy file with specific test document content
    verbose_echo "Generating dummy text file..."
    DUMMY_TEXT_FILE="${TEMP_DIRECTORY}scan_result.txt"
    # Generate content for the dummy text file
    {
        echo "--- Test Document ---"
        echo ""
        echo "This is a test document generated by the holtech_scan.sh script."
        echo "No actual scan has taken place."
        echo ""
        echo "Scan Simulation Details:"
        echo "  Timestamp: $(date +"%Y-%m-%d %H:%M:%S")"
        echo "  Machine: $(hostname)"
        echo "  User: $(whoami)"
        echo "  Operating System: $(uname -s)"
        echo "  Kernel Version: $(uname -r)"
        echo ""
        echo "This file is for testing purposes only."
        echo ""
        echo "---------------------"
        echo ""
        echo "Additional help (-h --help):"
        echo "${HELPTEXT}"
        echo ""
        echo "---------------------"
    } > "${DUMMY_TEXT_FILE}" # Redirect all echoes to the dummy text file

    verbose_echo "Converting dummy text file to PDF..."
    convert "TEXT:${DUMMY_TEXT_FILE}" "${OUTPUT_DIRECTORY}${FILENAME}"
    PDF_CREATED=1
fi

# Remove temporary files
verbose_echo "Removing temp files..."
rm -r "${TEMP_DIRECTORY}"

# --- Post-creation Actions ---
# Open the created PDF if the -o argument was provided and PDF was created
if [[ "$OPEN_FILE" -eq 1 && "$PDF_CREATED" -eq 1 ]]; then
    if [[ -f "${OUTPUT_DIRECTORY}${FILENAME}" ]]; then # Check if PDF exists (it should!)
        verbose_echo "Opening generated PDF: ${OUTPUT_DIRECTORY}${FILENAME}"
        xdg-open "${OUTPUT_DIRECTORY}" &>/dev/null & # Open folder
        xdg-open "${OUTPUT_DIRECTORY}${FILENAME}" &>/dev/null & # Open file
    else
        tstamp_echo "Error: Cannot open file. PDF was not found at ${OUTPUT_DIRECTORY}${FILENAME}" >&2
    fi
fi

# Print the created PDF if the -p argument was provided and PDF was created
if [[ "$PRINT_FILE" -eq 1 && "$PDF_CREATED" -eq 1 ]]; then
    if [[ -f "${OUTPUT_DIRECTORY}${FILENAME}" ]]; then # Check if PDF exists (it should!)
        verbose_echo "Sending PDF to printer: ${OUTPUT_DIRECTORY}${FILENAME}"
        # Capture stderr and exit status from lp command
        LP_OUTPUT=$(lp "${OUTPUT_DIRECTORY}${FILENAME}" 2>&1)
        LP_STATUS=$?

        # Status code not succesful
        if [[ "$LP_STATUS" -ne 0 ]]; then
            tstamp_echo "Error: Failed to send PDF to printer. lp exit code: $LP_STATUS" >&2
            tstamp_echo "lp command output: $LP_OUTPUT" >&2

            # If the error is because of no default destination
            if echo "$LP_OUTPUT" | grep -q "No default destination"; then
                tstamp_echo "${PRINTERTEXT}";
            fi
        else
            verbose_echo "PDF successfully sent to printer."
        fi
    else
        tstamp_echo "Error: Cannot print file. PDF was not found at ${OUTPUT_DIRECTORY}${FILENAME}" >&2
    fi
fi

tstamp_echo "Done."