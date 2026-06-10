declare global {
  namespace App {
    interface Locals {
      user: {
        name: string | null;
        id: string | null;
        email: string | null;
      } | null;
    }
  }
}

export {};
