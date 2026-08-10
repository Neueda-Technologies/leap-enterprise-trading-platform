/**
 * Token verification: is this caller who they say they are.
 *
 * <p>Single responsibility: read the {@code Authorization} header, verify the signature, the expiry
 * and the algorithm the token asks for, in that order, and make the verified identity available to
 * the layers below. Nothing here reads the database and nothing here decides what a caller may
 * reach.
 *
 * <p>Verification runs for every route under {@code /api/v1/}, before any controller does, so that
 * a route added next sprint is protected before anyone writes its handler. A missing header, a
 * wrong scheme, an expired token and a forged signature are one answer, {@code AUTH-401}, with one
 * body. Four different messages tell an attacker which of the four they got wrong.
 *
 * <p>Whether the caller may reach the account named in the request is a different question with a
 * different answer, {@code ACC-403}, and it belongs in the service layer where the account key is
 * known.
 */
package com.tradingplatform.tradeapi.security;
