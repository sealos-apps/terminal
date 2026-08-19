import type { GetServerSideProps } from 'next';

export default function Healthz() {
  return <span>ok</span>;
}

export const getServerSideProps: GetServerSideProps = async ({ res }) => {
  res.statusCode = 200;
  return { props: {} };
};
