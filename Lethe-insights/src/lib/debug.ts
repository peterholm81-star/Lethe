/**
 * Debug logging for Lethe Insights
 * 
 * Only logs when VITE_DEBUG_INSIGHTS=true in .env.local
 * 
 * Usage:
 *   import { dlog } from '../lib/debug';
 *   dlog('[MyComponent] data loaded', data);
 */

export const DEBUG_INSIGHTS = import.meta.env.VITE_DEBUG_INSIGHTS === 'true';

/**
 * Debug log - only outputs when DEBUG_INSIGHTS is true
 */
export function dlog(...args: unknown[]): void {
  if (DEBUG_INSIGHTS) {
    console.log(...args);
  }
}

/**
 * Debug warn - only outputs when DEBUG_INSIGHTS is true
 */
export function dwarn(...args: unknown[]): void {
  if (DEBUG_INSIGHTS) {
    console.warn(...args);
  }
}
