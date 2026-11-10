// Ideb das escolas municipais (INEP) — página pública.
import { PageHeader } from '@/components/ui';
import { IdebRedePainel } from '@/components/ideb';

export default function Ideb() {
  return (
    <div>
      <PageHeader eyebrow="Dado oficial do INEP" title="Ideb da rede municipal"
        subtitle="Índice de Desenvolvimento da Educação Básica dos anos iniciais (1º ao 5º ano), de 2005 a 2025: a rede de Maringá e cada escola, com aprovação e notas do Saeb." />
      <IdebRedePainel />
    </div>
  );
}
