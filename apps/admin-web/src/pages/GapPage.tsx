import { Button, Card, PageHeader } from '../components/ui';

export function GapPage({ feature }: { feature: string }) {
  return (
    <>
      <PageHeader title={feature} subtitle="Not exposed by the backend in this environment." />
      <Card style={{ padding: 16, maxWidth: 620 }}>
        <p style={{ color: 'var(--sw-text-2)' }}>
          The backend does not currently expose an admin API for <strong>{feature}</strong>,
          so there is nothing safe to operate on here. Creating fake controls or invented
          endpoints would violate the project rule that the backend remains the authority.
        </p>
        <p style={{ color: 'var(--sw-text-muted)', fontSize: 13, marginTop: 8 }}>
          If this is required, the first step is to design the API contract in the Django
          backend, then wire this page to it.
        </p>
        <Button variant="secondary" onClick={() => window.history.back()} style={{ marginTop: 4 }}>
          Go back
        </Button>
      </Card>
    </>
  );
}