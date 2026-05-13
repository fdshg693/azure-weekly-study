import type { Handle } from '@sveltejs/kit';

// App Service Easy Auth が付与するヘッダから現在ユーザーを抽出する。
// ローカル開発時はヘッダが無いため null。
export const handle: Handle = async ({ event, resolve }) => {
  const principalName = event.request.headers.get('x-ms-client-principal-name');
  const principalId = event.request.headers.get('x-ms-client-principal-id');
  const principalEmail =
    event.request.headers.get('x-ms-client-principal-idp') === 'aad'
      ? event.request.headers.get('x-ms-client-principal-name')
      : null;

  event.locals.user = principalName
    ? { name: principalName, id: principalId, email: principalEmail }
    : null;

  return resolve(event);
};
