#!/usr/bin/env python3

import aisuite as ai
import sys
import os
import datetime

client = ai.Client()

client.configure({
    "ollama": {
        "timeout": 6000,  # Set timeout to 600 seconds (10 minutes)
    },
    "xai": {
        "timeout": 600,  # Set timeout to 600 seconds (10 minutes)
    }
})

def ask_from_file(model, temperature, system_prompt_file, user_prompt_file):
    """
    Send a prompt to LLM and get a response.
    """
    try:
        # Read the contents of the prompt files
        system_prompt = system_prompt_file.read()
        user_prompt = user_prompt_file.read()

        # Create the messages to send to the model
        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ]

        # Call the AI model to get a response
        response = client.chat.completions.create(
            model=model,
            messages=messages,
            temperature=temperature,
        )

        # Return the response content
        return response.choices[0].message.content.strip()
    except Exception as e:
        # Print any errors that occur
        print(f"Error: {e}", file=sys.stderr)
        return None


def generate_output_filename(model, temperature, user_prompt_file_path, output_dir):
    """Generate a timestamped filename."""
    # Extract the model name part after the colon, if present
    model_name = model.split(":")[1] if ":" in model else model
    # Generate a timestamp
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    # Create the output filename
    user_prompt_file_path = os.path.basename(user_prompt_file_path).replace("user_prompt-", "")
    return os.path.join(output_dir, f"{model_name}_{temperature}_{user_prompt_file_path}_{timestamp}.tf")


if __name__ == "__main__":
    # Check if the correct number of arguments are provided
    if len(sys.argv) != 7:
        print(
            "Usage: llm_client.py <system_prompt_file> "
            "<user_prompt_file> <output_log_dir> <num_calls> <model> <temperature>"
        )
        sys.exit(1)

    # Get the command line arguments
    system_prompt_file_path = sys.argv[1]
    user_prompt_file_path = sys.argv[2]
    output_log_dir = sys.argv[3]
    num_calls = int(sys.argv[4])
    model = sys.argv[5]
    temperature = float(sys.argv[6])

    # Ensure the output directory exists
    os.makedirs(output_log_dir, exist_ok=True)

    # Loop to make the specified number of calls to the AI provider
    for _ in range(num_calls):
        with open(system_prompt_file_path, "r") as system_prompt_file, open(
            user_prompt_file_path, "r"
        ) as user_prompt_file:
            # Get the response from the AI model
            result = ask_from_file(
                model=model,
                temperature=temperature,
                system_prompt_file=system_prompt_file,
                user_prompt_file=user_prompt_file,
            )

            if result:
                # Generate the output filename and save the response
                output_filename = generate_output_filename(model, temperature, user_prompt_file_path, output_log_dir)
                with open(output_filename, "w") as f:
                    f.write(result)
                print(f"Response saved to {output_filename} {_+1}/{num_calls}")
