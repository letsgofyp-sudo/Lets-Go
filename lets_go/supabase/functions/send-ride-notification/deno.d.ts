// deno-lint-ignore-file
// deno-lint-ignore no-explicit-any

// Basic Deno types
declare const Deno: {
  env: {
    get(key: string): string | undefined;
    set(key: string, value: string): void;
    toObject(): { [key: string]: string };
    delete(key: string): void;
  };
  exit(code?: number): never;
};

// Web API globals
declare const console: Console;
declare const fetch: typeof globalThis.fetch;
declare const Response: typeof globalThis.Response;
declare const Request: typeof globalThis.Request;

declare interface Console {
  log(message?: any, ...optionalParams: any[]): void;
  error(message?: any, ...optionalParams: any[]): void;
  warn(message?: any, ...optionalParams: any[]): void;
  info(message?: any, ...optionalParams: any[]): void;
  debug(message?: any, ...optionalParams: any[]): void;
}

// Add type definitions for the Supabase client
declare module 'https://esm.sh/@supabase/supabase-js@2.39.0' {
  export function createClient(
    supabaseUrl: string,
    supabaseKey: string,
    options?: any
  ): any;
}

// Add type definitions for Deno's HTTP server
declare module 'https://deno.land/std@0.177.0/http/server.ts' {
  export function serve(handler: (req: Request) => Promise<Response> | Response, options?: any): Promise<void>;
}
