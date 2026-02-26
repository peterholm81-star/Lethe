import { createClient } from "@supabase/supabase-js";
import { dlog } from "./debug";

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string;

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error("Missing Supabase environment variables");
}

dlog("[Supabase] Connecting to:", supabaseUrl);

export const supabase = createClient(supabaseUrl, supabaseAnonKey);
