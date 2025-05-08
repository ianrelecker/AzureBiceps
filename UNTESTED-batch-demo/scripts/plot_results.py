#!/usr/bin/env python3
"""
Results Visualization for Azure Batch Monte Carlo Pi Demo
This script creates visualizations from the aggregate results.
"""

import argparse
import json
import math
import matplotlib.pyplot as plt
import numpy as np
import os
from datetime import datetime

def plot_convergence(results, output_dir='.'):
    """
    Plot the convergence of Pi estimation as more points are added.
    
    Args:
        results: Aggregated results dictionary
        output_dir: Directory for output files
    """
    # Extract data from individual results
    individual_results = sorted(results['individual_results'], key=lambda x: int(x['task_id']))
    
    # Accumulate points and track error
    cumulative_points = [0]
    cumulative_inside = [0]
    pi_estimates = [0]
    errors = [math.pi]  # Initial error is pi itself (0 estimate)
    
    for result in individual_results:
        cumulative_points.append(cumulative_points[-1] + result['total_points'])
        cumulative_inside.append(cumulative_inside[-1] + result['points_inside_circle'])
        pi_estimate = 4 * cumulative_inside[-1] / cumulative_points[-1]
        pi_estimates.append(pi_estimate)
        errors.append(abs(pi_estimate - math.pi))
    
    # Remove the first zero point
    cumulative_points = cumulative_points[1:]
    pi_estimates = pi_estimates[1:]
    errors = errors[1:]
    
    # Plot Pi estimation convergence
    plt.figure(figsize=(12, 6))
    plt.subplot(1, 2, 1)
    plt.plot(cumulative_points, pi_estimates, 'b-', linewidth=2)
    plt.axhline(y=math.pi, color='r', linestyle='--', label=f'π = {math.pi:.10f}')
    plt.xscale('log')
    plt.xlabel('Number of Points (log scale)')
    plt.ylabel('Pi Estimation')
    plt.title('Convergence of Pi Estimation')
    plt.grid(True, alpha=0.3)
    plt.legend()
    
    # Plot error convergence
    plt.subplot(1, 2, 2)
    plt.plot(cumulative_points, errors, 'r-', linewidth=2)
    plt.xscale('log')
    plt.yscale('log')
    plt.xlabel('Number of Points (log scale)')
    plt.ylabel('Absolute Error (log scale)')
    plt.title('Error Convergence')
    plt.grid(True, alpha=0.3)
    
    plt.tight_layout()
    
    # Save plot
    filename = os.path.join(output_dir, 'pi_convergence.png')
    plt.savefig(filename, dpi=150)
    plt.close()
    
    return filename

def plot_task_distribution(results, output_dir='.'):
    """
    Plot the distribution of tasks, points, and execution times.
    
    Args:
        results: Aggregated results dictionary
        output_dir: Directory for output files
    """
    # Extract data from individual results
    individual_results = sorted(results['individual_results'], key=lambda x: int(x['task_id']))
    
    task_ids = [r['task_id'] for r in individual_results]
    points = [r['total_points'] for r in individual_results]
    exec_times = [r.get('execution_time_seconds', 0) for r in individual_results]
    pi_estimates = [r['pi_estimation'] for r in individual_results]
    errors = [abs(r['pi_estimation'] - math.pi) for r in individual_results]
    
    # Create figure with multiple subplots
    plt.figure(figsize=(15, 10))
    
    # Plot points distribution
    plt.subplot(2, 2, 1)
    plt.bar(task_ids, points, color='skyblue')
    plt.xlabel('Task ID')
    plt.ylabel('Number of Points')
    plt.title('Points Distribution Across Tasks')
    plt.grid(True, alpha=0.3)
    plt.xticks(rotation=45)
    
    # Plot execution time
    plt.subplot(2, 2, 2)
    plt.bar(task_ids, exec_times, color='orange')
    plt.xlabel('Task ID')
    plt.ylabel('Execution Time (seconds)')
    plt.title('Execution Time By Task')
    plt.grid(True, alpha=0.3)
    plt.xticks(rotation=45)
    
    # Plot individual pi estimates
    plt.subplot(2, 2, 3)
    plt.bar(task_ids, pi_estimates, color='green')
    plt.axhline(y=math.pi, color='r', linestyle='--', label=f'π = {math.pi:.10f}')
    plt.xlabel('Task ID')
    plt.ylabel('Pi Estimation')
    plt.title('Individual Task Pi Estimates')
    plt.grid(True, alpha=0.3)
    plt.xticks(rotation=45)
    plt.legend()
    
    # Plot individual errors
    plt.subplot(2, 2, 4)
    plt.bar(task_ids, errors, color='red')
    plt.xlabel('Task ID')
    plt.ylabel('Absolute Error')
    plt.title('Absolute Error By Task')
    plt.grid(True, alpha=0.3)
    plt.xticks(rotation=45)
    
    plt.tight_layout()
    
    # Save plot
    filename = os.path.join(output_dir, 'task_distribution.png')
    plt.savefig(filename, dpi=150)
    plt.close()
    
    return filename

def plot_performance_summary(results, output_dir='.'):
    """
    Create a summary visualization of the Pi estimation performance.
    
    Args:
        results: Aggregated results dictionary
        output_dir: Directory for output files
    """
    # Create figure
    plt.figure(figsize=(12, 10))
    
    # Add title with summary information
    plt.suptitle(f"Monte Carlo Pi Estimation Summary\n"
                f"Total Tasks: {results['task_count']}, "
                f"Total Points: {results['total_points']:,}", 
                fontsize=16)
    
    # Format statistics for display
    stats_text = (
        f"Final Pi Estimation: {results['pi_estimation']:.10f}\n"
        f"True Pi: {math.pi:.10f}\n"
        f"Absolute Error: {results['absolute_error']:.10f}\n"
        f"Relative Error: {results['relative_error_percent']:.8f}%\n"
        f"Points Inside Circle: {results['points_inside_circle']:,}\n"
        f"Total Points: {results['total_points']:,}\n"
        f"Ratio: {results['points_inside_circle']/results['total_points']:.6f}"
    )
    
    # Create a text box for statistics
    plt.figtext(0.5, 0.85, stats_text, 
                bbox=dict(facecolor='white', alpha=0.8, boxstyle='round,pad=0.5'),
                ha='center', fontsize=12)
    
    # Plot a pie chart illustrating the ratio
    plt.subplot(2, 1, 2)
    inside = results['points_inside_circle']
    outside = results['total_points'] - inside
    plt.pie([inside, outside], 
            labels=[f'Inside Circle\n{inside:,} points', f'Outside Circle\n{outside:,} points'],
            colors=['red', 'blue'],
            autopct='%1.2f%%',
            startangle=90,
            explode=(0.1, 0))
    plt.axis('equal')
    plt.title(f"Distribution of {results['total_points']:,} Points")
    
    # Save plot
    filename = os.path.join(output_dir, 'performance_summary.png')
    plt.savefig(filename, dpi=150, bbox_inches='tight')
    plt.close()
    
    return filename

def main():
    """Main function to parse arguments and generate visualizations"""
    parser = argparse.ArgumentParser(description='Generate visualizations from Monte Carlo Pi results')
    parser.add_argument('-i', '--input_file', type=str, default='aggregate_results.json',
                        help='Input aggregate results JSON file (default: aggregate_results.json)')
    parser.add_argument('-o', '--output_dir', type=str, default='.',
                        help='Directory for output files')
    
    args = parser.parse_args()
    
    # Ensure output directory exists
    os.makedirs(args.output_dir, exist_ok=True)
    
    # Load aggregate results
    try:
        with open(args.input_file, 'r') as f:
            results = json.load(f)
    except FileNotFoundError:
        print(f"Error: Input file '{args.input_file}' not found")
        return
    except json.JSONDecodeError:
        print(f"Error: Input file '{args.input_file}' is not valid JSON")
        return
    
    # Generate visualizations
    print("Generating visualizations...")
    
    convergence_plot = plot_convergence(results, args.output_dir)
    print(f"Created convergence plot: {convergence_plot}")
    
    distribution_plot = plot_task_distribution(results, args.output_dir)
    print(f"Created task distribution plot: {distribution_plot}")
    
    summary_plot = plot_performance_summary(results, args.output_dir)
    print(f"Created performance summary: {summary_plot}")
    
    print("Visualization complete.")

if __name__ == "__main__":
    main()
