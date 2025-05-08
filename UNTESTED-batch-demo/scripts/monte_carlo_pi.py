#!/usr/bin/env python3
"""
Monte Carlo Pi Estimation - Sample HPC workload for Azure Batch
This script estimates Pi by randomly placing points in a square and counting
how many fall within the inscribed circle.
"""

import argparse
import json
import math
import numpy as np
import os
import time
import matplotlib.pyplot as plt
from datetime import datetime

def estimate_pi(num_points, task_id=0, plot_points=False, max_plot_points=10000):
    """
    Estimate Pi using Monte Carlo method.
    
    Args:
        num_points: Number of random points to generate
        task_id: Optional task identifier for tracking
        plot_points: Whether to generate a visualization plot
        max_plot_points: Maximum number of points to include in visualization
    
    Returns:
        Tuple containing (pi_estimation, points_in_circle, points_total, plot_filename)
    """
    start_time = time.time()

    # For plotting, use a smaller subset if we have many points
    plot_sample = min(num_points, max_plot_points)
    
    # Generate random points
    points_in_circle = 0
    
    # Arrays for plotting if needed
    if plot_points:
        plot_x = np.zeros(plot_sample)
        plot_y = np.zeros(plot_sample)
        plot_colors = np.zeros(plot_sample, dtype=str)
    
    # Main calculation loop
    for i in range(num_points):
        # Generate random point in square from (-1,-1) to (1,1)
        x = np.random.uniform(-1, 1)
        y = np.random.uniform(-1, 1)
        
        # Check if point is in circle
        distance = x**2 + y**2
        is_in_circle = distance <= 1
        
        if is_in_circle:
            points_in_circle += 1
        
        # Store data for plotting (only for a subset of points)
        if plot_points and i < plot_sample:
            plot_x[i] = x
            plot_y[i] = y
            plot_colors[i] = 'red' if is_in_circle else 'blue'
    
    # Calculate pi estimation: (points in circle / total points) * 4
    pi_estimation = (points_in_circle / num_points) * 4
    
    # Create visualization if requested
    plot_filename = None
    if plot_points:
        plot_filename = f"pi_estimation_task{task_id}.png"
        create_visualization(plot_x, plot_y, plot_colors, pi_estimation, points_in_circle, 
                            num_points, plot_filename)
    
    execution_time = time.time() - start_time
    
    return pi_estimation, points_in_circle, num_points, execution_time, plot_filename

def create_visualization(x, y, colors, pi_estimation, points_in_circle, total_points, filename):
    """Create a visualization of the Monte Carlo simulation"""
    plt.figure(figsize=(10, 10))
    
    # Plot circle
    circle = plt.Circle((0, 0), 1, fill=False, color='black', linewidth=2)
    plt.gca().add_patch(circle)
    
    # Plot points
    plt.scatter(x, y, c=colors, alpha=0.5)
    
    # Add square boundary
    plt.axhline(y=-1, color='black', linestyle='-', linewidth=2)
    plt.axhline(y=1, color='black', linestyle='-', linewidth=2)
    plt.axvline(x=-1, color='black', linestyle='-', linewidth=2)
    plt.axvline(x=1, color='black', linestyle='-', linewidth=2)
    
    # Add title and info
    plt.title(f"Monte Carlo Pi Estimation\nEstimated π = {pi_estimation:.10f}\nTrue π = {math.pi:.10f}\nError = {abs(pi_estimation - math.pi):.10f}",
             fontsize=14)
    
    # Add annotation with statistics
    plt.annotate(f"Points inside circle: {points_in_circle}\nTotal points: {total_points}\nRatio: {points_in_circle/total_points:.6f}",
                xy=(0.5, 0.02),
                xycoords='axes fraction',
                bbox=dict(boxstyle="round,pad=0.5", fc="white", alpha=0.8),
                fontsize=12)
    
    # Set axis limits and labels
    plt.xlim(-1.1, 1.1)
    plt.ylim(-1.1, 1.1)
    plt.xlabel('X')
    plt.ylabel('Y')
    plt.grid(True, alpha=0.3)
    plt.axis('equal')  # Equal aspect ratio
    
    # Save plot
    plt.savefig(filename, dpi=150)
    plt.close()

def main():
    """Main function to parse arguments and run estimation"""
    parser = argparse.ArgumentParser(description='Estimate Pi using Monte Carlo method')
    parser.add_argument('-n', '--num_points', type=int, default=1000000,
                        help='Number of random points to generate')
    parser.add_argument('-t', '--task_id', type=str, default='0',
                        help='Task identifier for output naming')
    parser.add_argument('-o', '--output_dir', type=str, default='.',
                        help='Directory for output files')
    parser.add_argument('-p', '--plot', action='store_true',
                        help='Generate visualization plot')
    
    args = parser.parse_args()
    
    # Ensure output directory exists
    os.makedirs(args.output_dir, exist_ok=True)
    
    # Run estimation
    pi_est, points_in, points_total, exec_time, plot_file = estimate_pi(
        args.num_points, args.task_id, args.plot)
    
    # Prepare result data
    result = {
        'task_id': args.task_id,
        'timestamp': datetime.now().isoformat(),
        'pi_estimation': pi_est,
        'true_pi': math.pi,
        'absolute_error': abs(pi_est - math.pi),
        'relative_error_percent': abs(pi_est - math.pi) / math.pi * 100,
        'points_inside_circle': points_in,
        'total_points': points_total,
        'execution_time_seconds': exec_time,
        'plot_file': plot_file
    }
    
    # Save result to JSON file
    output_file = os.path.join(args.output_dir, f"pi_result_task{args.task_id}.json")
    with open(output_file, 'w') as f:
        json.dump(result, f, indent=2)
    
    # Also print to stdout
    print(f"Task {args.task_id} completed:")
    print(f"Pi Estimation: {pi_est:.10f} (True Pi: {math.pi:.10f})")
    print(f"Absolute Error: {abs(pi_est - math.pi):.10f}")
    print(f"Points inside circle: {points_in} / {points_total}")
    print(f"Execution time: {exec_time:.2f} seconds")
    print(f"Results saved to: {output_file}")
    if plot_file:
        plot_path = os.path.join(args.output_dir, plot_file)
        print(f"Plot saved to: {plot_path}")

if __name__ == "__main__":
    main()
