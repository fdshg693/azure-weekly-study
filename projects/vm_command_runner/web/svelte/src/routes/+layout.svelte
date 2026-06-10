<script lang="ts">
  import type { LayoutData } from './$types';
  let { data, children }: { data: LayoutData; children: any } = $props();
</script>

<header>
  <h1>VM Command Console</h1>
  {#if data.user}
    <div class="user">
      Signed in as <strong>{data.user.name}</strong>
      <a href="/.auth/logout">Logout</a>
    </div>
  {/if}
</header>

<main>
  {@render children()}
</main>

<style>
  :global(body) {
    margin: 0;
    font-family: system-ui, -apple-system, 'Segoe UI', sans-serif;
    background: #f5f6f8;
    color: #1f2330;
  }
  header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0.75rem 1.5rem;
    background: #1f2330;
    color: #fff;
  }
  header h1 {
    font-size: 1.1rem;
    margin: 0;
  }
  .user {
    font-size: 0.85rem;
  }
  .user a {
    color: #9bd1ff;
    margin-left: 0.5rem;
  }
  main {
    max-width: 960px;
    margin: 1.5rem auto;
    padding: 0 1rem;
  }
</style>
