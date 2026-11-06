import { useEffect } from 'react';
import { motion, useReducedMotion } from 'motion/react';
import { IaraMascot } from '@/components/iara';
import Splash from './Splash';

// Abertura provisória do site, para a apresentação em Umuarama: a mesma tela, com o Umuaraminha ao lado da Ipê.
// Para voltar à original: em router.tsx, a rota /abertura volta a usar <Splash />. Depois, apagar este arquivo, a pasta public/umuarama e a rota /umuarama.

const RAZAO_UMU = 386 / 706;
const RAZAO_IPE = 778 / 900;
const PIVO_BRACO = '71.09% 43.39%'; // punho da camiseta, relativo à arte recortada

function IpeEUmuaraminha() {
  const reduce = useReducedMotion();
  const vw = typeof window !== 'undefined' ? window.innerWidth : 480;
  const vh = typeof window !== 'undefined' ? window.innerHeight : 800;
  const alturaIpe = Math.round(Math.min(430, vh * 0.5, (Math.min(vw, 560) - 24) / 1.25));
  const alturaUmu = Math.round(alturaIpe * 0.9);
  const larguraUmu = Math.round(alturaUmu * RAZAO_UMU);
  const sobreposicao = Math.round(alturaIpe * 0.16);

  return (
    <div className="relative flex items-end justify-center" style={{ width: Math.round(alturaIpe * RAZAO_IPE) + larguraUmu - sobreposicao }}>
      {/* a arte oficial da Ipê, espelhada: a mão que acena fica para fora e o livro, que ela segura, fica do lado do amigo */}
      <div style={{ transform: 'rotate(2deg)', transformOrigin: '50% 100%' }}>
        <div style={{ transform: 'scaleX(-1)' }}>
          <IaraMascot height={alturaIpe} mood="wave" entrance delay={reduce ? 0 : 0.5} />
        </div>
      </div>

      <motion.div
        className="relative select-none"
        style={{ width: larguraUmu, height: alturaUmu, marginLeft: -sobreposicao, rotate: -2, transformOrigin: '50% 100%' }}
        initial={reduce ? false : { opacity: 0, y: 40, scale: 0.92 }}
        animate={{ opacity: 1, y: 0, scale: 1 }}
        transition={{ type: 'spring', stiffness: 120, damping: 16, delay: reduce ? 0 : 0.8 }}
        aria-hidden
      >
        <motion.div
          className="absolute inset-0"
          style={{ transformOrigin: '50% 98%' }}
          animate={reduce ? {} : { rotate: [0, -0.9, 0, 0.9, 0] }}
          transition={{ duration: 7, repeat: Infinity, ease: 'easeInOut' }}
        >
          <motion.img
            src="./umuarama/umuaraminha-braco.webp"
            alt=""
            draggable={false}
            className="absolute inset-0 h-full w-full"
            style={{ transformOrigin: PIVO_BRACO }}
            animate={reduce ? { rotate: 0 } : { rotate: [0, 12, -6, 12, -3, 8, 0] }}
            transition={{ duration: 2.2, delay: reduce ? 0 : 2.3, repeat: Infinity, repeatDelay: 4.5, ease: 'easeInOut' }}
          />
          <img src="./umuarama/umuaraminha-corpo.webp" alt="" draggable={false} className="absolute inset-0 h-full w-full" />
        </motion.div>
      </motion.div>
    </div>
  );
}

export default function AberturaUmuarama() {
  useEffect(() => {
    const antes = document.title;
    document.title = 'IARA Educa · Umuarama';
    return () => { document.title = antes; };
  }, []);

  return <Splash cidade="Umuarama" figura={<IpeEUmuaraminha />} />;
}
