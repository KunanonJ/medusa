import React from 'react';
import { ThemeProvider } from 'theme-ui';
import theme from 'theme';

import SEO from 'components/seo';
import Layout from 'components/layout';
import Banner from '../sections/banner';
import ChainSuport from '../sections/key-feature';
import ServiceSection from '../sections/service-section';
import Feature from '../sections/feature';
import TokenDistribution from '../sections/core-feature';
import RoadMap from '../sections/workflow';
import Package from '../sections/package';
import TeamSection from '../sections/team-section';
import TestimonialCard from '../sections/testimonial';


export default function IndexPage() {
  return (
    <ThemeProvider theme={theme}>
        <Layout>
          <SEO title="Zapblink" />
          <Banner />
          {/* <ServiceSection /> */}
          {/* <Feature /> */}
          <RoadMap />
          <Package />
          <TokenDistribution />
          {/* <ChainSuport /> */}
          <TeamSection />
          {/* <TestimonialCard /> */}
        </Layout>
    </ThemeProvider>
  );
}