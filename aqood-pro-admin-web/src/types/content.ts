export interface LegalLinks {
  privacy: string;
  terms: string;
  refund: string;
  accountDeletion: string;
}

export interface AppContentConfig {
  homeGreetingPrefix?: string;
  homeWelcome?: string;
  homeHeroTitle?: string;
  homeHeroSubtitle?: string;
  homeHeroButtonText?: string;
  homeServicesTitle?: string;
  homeServicesAction?: string;
  serviceResidentialTitle?: string;
  serviceResidentialSubtitle?: string;
  serviceCommercialTitle?: string;
  serviceCommercialSubtitle?: string;
  serviceRenewalTitle?: string;
  serviceRenewalSubtitle?: string;
  serviceRenewalMessage?: string;
  serviceHandoverTitle?: string;
  serviceHandoverSubtitle?: string;
  serviceHandoverMessage?: string;
  homePropertiesTitle?: string;
  homePropertiesAction?: string;
  homeEmptyPropertiesTitle?: string;
  homeEmptyPropertiesSubtitle?: string;
  homeEmptyPropertiesAction?: string;
  homeContractsTitle?: string;
  homeContractsAction?: string;
  homeEmptyContractsTitle?: string;
  homeEmptyContractsSubtitle?: string;
  homeEmptyContractsAction?: string;
  supportInfo?: string;
  maintenanceMode?: boolean;
  legalLinks?: LegalLinks;
  [key: string]: unknown;
}

export const DEFAULT_LEGAL_LINKS: LegalLinks = {
  privacy: 'https://ejarz-pro-20260624.web.app/legal/privacy',
  terms: 'https://ejarz-pro-20260624.web.app/legal/terms',
  refund: 'https://ejarz-pro-20260624.web.app/legal/refund',
  accountDeletion: 'https://ejarz-pro-20260624.web.app/legal/account-deletion',
};
