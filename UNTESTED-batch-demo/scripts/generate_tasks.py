#!/usr/bin/env python3
"""
Task Generator for Azure Batch Monte Carlo Pi Demo
This script creates task specifications for the Monte Carlo Pi estimation workload.
"""

import argparse
import json
import os

def generate_tasks(total_points, num_tasks, task_points_min=None):
    """
    Generate tasks for Monte Carlo Pi estimation.
    
    Args:
        total_points: Total number of points to simulate
        num_tasks: Number of tasks to generate
        task_points_min: Minimum points per task (optional)
    
    Returns:
        List of task specifications
    """
    # If task_points_min is provided, adjust num_tasks if necessary
    if task_points_min is not None:
        max_tasks = total_points // task_points_min
        if max_tasks < num_tasks:
            print(f"Warning: Reducing number of tasks from {num_tasks} to {max_tasks} " 
                  f"to ensure at least {task_points_min} points per task")
            num_tasks = max_tasks
    
    # Calculate points per task (approximately)
    base_points_per_task = total_points // num_tasks
    remainder = total_points % num_tasks
    
    tasks = []
    points_assigned = 0
    
    for i in range(num_tasks):
        # Distribute remainder points across tasks
        task_points = base_points_per_task + (1 if i < remainder else 0)
        
        # Build task specification
        task_id = f"{i+1:04d}"
        task_name = f"pi-task-{task_id}"
        
        command = f"python3 $AZ_BATCH_APP_PACKAGE_montecarlo/monte_carlo_pi.py" \
                 f" -n {task_points}" \
                 f" -t {task_id}" \
                 f" -o $AZ_BATCH_TASK_WORKING_DIR" \
                 f" -p"
        
        task = {
            "id": task_id,
            "display_name": task_name,
            "command_line": command,
            "resource_files": [],
            "output_files": [
                {
                    "file_pattern": "*.json",
                    "destination": {
                        "container": {
                            "container_url": "$CONTAINER_SAS_URL"
                        }
                    },
                    "upload_options": {
                        "upload_condition": "taskCompletion"
                    }
                },
                {
                    "file_pattern": "*.png",
                    "destination": {
                        "container": {
                            "container_url": "$CONTAINER_SAS_URL"
                        }
                    },
                    "upload_options": {
                        "upload_condition": "taskCompletion"
                    }
                }
            ]
        }
        
        tasks.append(task)
        points_assigned += task_points
    
    # Verify total points match
    assert points_assigned == total_points, f"Point allocation error: {points_assigned} != {total_points}"
    
    return tasks

def create_merge_task(num_tasks, output_file="aggregate_results.json"):
    """
    Create a merge task that depends on all other tasks and aggregates results.
    
    Args:
        num_tasks: Number of task dependencies
        output_file: Name of the output file
    
    Returns:
        Task specification for the merge task
    """
    # Task IDs for dependencies (formatted to match task IDs)
    task_ids = [f"{i+1:04d}" for i in range(num_tasks)]
    
    # Create dependency list
    task_dependencies = {
        "task_ids": task_ids
    }
    
    # Python script for merging (as a multi-line command string)
    merge_script = r"""
python3 -c "
import json
import os
import math

# Get all result files
result_files = [f for f in os.listdir('.') if f.startswith('pi_result_task') and f.endswith('.json')]
print(f'Found {len(result_files)} result files')

# Load results from all tasks
results = []
for filename in result_files:
    with open(filename, 'r') as f:
        results.append(json.load(f))

if not results:
    print('No results found!')
    exit(1)

# Aggregate data
total_points = sum(r['total_points'] for r in results)
total_inside = sum(r['points_inside_circle'] for r in results)
pi_estimation = (total_inside / total_points) * 4
error = abs(pi_estimation - math.pi)

# Create aggregate result
aggregate = {
    'task_count': len(results),
    'total_points': total_points,
    'points_inside_circle': total_inside,
    'pi_estimation': pi_estimation,
    'true_pi': math.pi,
    'absolute_error': error,
    'relative_error_percent': error / math.pi * 100,
    'individual_results': results
}

# Save aggregate result
with open('aggregate_results.json', 'w') as f:
    json.dump(aggregate, f, indent=2)

print(f'Final Pi Estimation: {pi_estimation:.10f} (True Pi: {math.pi:.10f})')
print(f'Absolute Error: {error:.10f}')
print(f'Total Points: {total_points:,}')
print(f'Points Inside Circle: {total_inside:,}')
print(f'Ratio: {total_inside/total_points:.6f}')
print(f'Results saved to: aggregate_results.json')
"
"""
    
    # Create the merge task
    merge_task = {
        "id": "merge-task",
        "display_name": "Merge Results",
        "command_line": merge_script.strip(),
        "depends_on": task_dependencies,
        "output_files": [
            {
                "file_pattern": "aggregate_results.json",
                "destination": {
                    "container": {
                        "container_url": "$CONTAINER_SAS_URL"
                    }
                },
                "upload_options": {
                    "upload_condition": "taskCompletion"
                }
            }
        ]
    }
    
    return merge_task

def main():
    """Main function to parse arguments and generate task specifications"""
    parser = argparse.ArgumentParser(description='Generate tasks for Monte Carlo Pi estimation')
    parser.add_argument('-t', '--total_points', type=int, default=100000000,
                        help='Total number of points to simulate (default: 100M)')
    parser.add_argument('-n', '--num_tasks', type=int, default=10,
                        help='Number of tasks to generate (default: 10)')
    parser.add_argument('-m', '--min_points', type=int, default=1000000,
                        help='Minimum points per task (default: 1M)')
    parser.add_argument('-o', '--output_dir', type=str, default='.',
                        help='Directory for output files')
    parser.add_argument('--output_file', type=str, default='tasks.json',
                        help='Output JSON file name (default: tasks.json)')
    
    args = parser.parse_args()
    
    # Generate task specifications
    tasks = generate_tasks(args.total_points, args.num_tasks, args.min_points)
    
    # Create merge task
    merge_task = create_merge_task(len(tasks))
    
    # Add merge task to list
    tasks.append(merge_task)
    
    # Ensure output directory exists
    os.makedirs(args.output_dir, exist_ok=True)
    
    # Write tasks to JSON file
    output_path = os.path.join(args.output_dir, args.output_file)
    with open(output_path, 'w') as f:
        json.dump(tasks, f, indent=2)
    
    print(f"Generated {len(tasks)-1} calculation tasks + 1 merge task")
    print(f"Total points: {args.total_points:,}")
    print(f"Output written to: {output_path}")

if __name__ == "__main__":
    main()
