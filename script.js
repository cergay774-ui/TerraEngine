const reveals = document.querySelectorAll('.reveal');

const observer = new IntersectionObserver((entries) => {
  entries.forEach((entry) => {
    if (entry.isIntersecting) {
      entry.target.classList.add('visible');
      observer.unobserve(entry.target);
    }
  });
}, { threshold: 0.12 });

reveals.forEach((el, i) => {
  el.style.transitionDelay = `${Math.min(i * 35, 180)}ms`;
  observer.observe(el);
});

document.querySelector('.menu')?.addEventListener('click', () => {
  const nav = document.querySelector('.nav nav');
  if (!nav) return;
  const open = nav.classList.toggle('mobile-open');
  if (open) {
    nav.style.display = 'flex';
    nav.style.position = 'absolute';
    nav.style.top = '76px';
    nav.style.left = '0';
    nav.style.right = '0';
    nav.style.padding = '22px 24px';
    nav.style.background = '#0b0b0d';
    nav.style.borderBottom = '1px solid rgba(255,255,255,.1)';
    nav.style.flexDirection = 'column';
    nav.style.gap = '18px';
  } else {
    nav.removeAttribute('style');
  }
});

document.querySelectorAll('a[href^="#"]').forEach(link => {
  link.addEventListener('click', () => {
    const nav = document.querySelector('.nav nav');
    nav?.classList.remove('mobile-open');
    if (window.innerWidth <= 850 && nav) nav.removeAttribute('style');
  });
});
