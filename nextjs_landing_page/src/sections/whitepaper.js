/** @jsx jsx */
import whitepaper from 'assets/Zapblink-whitepaper.pdf'
import { Document, Page } from 'react-pdf';
import React, { useState } from 'react';

export default function whitepaper() {
  const [numPages, setNumPages] = useState(null);
  const [pageNumber, setPageNumber] = useState(1);

  function onDocumentLoadSuccess({ numPages }) {
    setNumPages(numPages);
  }

  return (
    <section id="Whitepaper">
         <Document
            file="Zapblink-whitepaper.pdf"
            onLoadSuccess={onDocumentLoadSuccess}
            >
                <Page pageNumber={pageNumber}/>
            </Document>
            <p>Page {pageNumber} of {numPages}</p>
    </section>
  );
}