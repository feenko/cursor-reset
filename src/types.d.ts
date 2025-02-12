declare global {
  interface CacheStorage {
    default: CacheStorage;
    put(request: Request, response: Response): Promise<void>;
  }
}

export { }
