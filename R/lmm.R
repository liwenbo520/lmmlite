# simple port of pyLMM to R

#' eigen decomposition + rotation
#'
#' Do eigen decomposition of kinship matrix and rotate `X` and
#' `y` by that, i.e., pre-multiply by the transpose of the matrix
#' of eigenvectors. If `Kva` and `Kve_t` provided, just do
#' the "rotation".
#'
#' @param K Kinship matrix (required if `use_cpp=TRUE`)
#' @param y Phenotypes
#' @param X Numeric matrix with covariates. If NULL, use a column
#' of 1's (for intercept).
#' @param Kva Eigenvalues of `K` (optional, ignored if `use_cpp=TRUE`)
#' @param Kve_t = transposed eigenvectors of K (optional, ignored if `use_cpp=TRUE`)
#' @param use_cpp = if TRUE, use c++ version of code
#'
#' @export
#' @return List containing `Kva`, `Kve_t` and rotated
#' `y` and `X`.
#'
#' @examples
#' data(recla)
#' e <- eigen_rotation(recla$kinship, recla$pheno[,1], recla$covar)
eigen_rotation <-
    function(K, y, X=NULL, Kva=NULL, Kve_t=NULL, use_cpp=TRUE)
{
    # check inputs
    if(use_cpp || is.null(Kva) || is.null(Kve_t)) {
        n <- nrow(K) # no. individuals
        stopifnot(ncol(K) == n) # square?
    }
    else {
        n <- nrow(Kve_t)
        stopifnot(ncol(Kve_t) == n) # square?
        stopifnot(length(Kva) == n)
    }
    if(!is.matrix(y)) y <- as.matrix(y)
    stopifnot(nrow(y) == n)

    if(is.null(X))
        X <- matrix(1, nrow=n)
    if(!is.matrix(X)) X <- as.matrix(X)
    stopifnot(nrow(X) == n)

    if(n==0) stop("need at least one individual")

    if(use_cpp) {
        result <- Rcpp_eigen_rotation(K, y, X)
        attr(result$X, "logdetXpX") <- Rcpp_calc_logdetXpX(result$X)
        return(result)
    }

    if(is.null(Kva) || is.null(Kve_t)) {
        # calculate eigen vals and vecs
        e <- eigen(K)
        Kva <- e$values
        Kve_t <- t(e$vectors)
    }
    # rotation
    y <- Kve_t %*% y
    X <- Kve_t %*% X

    list(Kva=Kva, Kve_t=Kve_t, y=y, X=X)
}


#' Get MLEs for coefficients and variance
#'
#' For a fixed value for `hsq`, the heritability, calculate the
#' corresponding maximum likelihood estimates of `beta` and
#' `sigmasq`, with the latter being the total variance,
#' `sigmasq_g + sigmasq_e`.
#'
#' @param hsq heritability
#' @param Kva eigenvalues of K (calculated by [eigen_rotation()])
#' @param y rotated phenotypes (calculated by [eigen_rotation()])
#' @param X rotated covariate matrix (calculated by [eigen_rotation()])
#' @param reml If TRUE, use REML; otherwise use ordinary maximum likelihood.
#' @param use_cpp = if TRUE, use c++ version of code
#'
#' @export
#' @return list containing `beta` and `sigmasq`, with residual
#' sum of squares and (if `reml=TRUE`, `log det (XSX)`) as
#' attributes.
#'
#' @examples
#' data(recla)
#' e <- eigen_rotation(recla$kinship, recla$pheno[,1], recla$covar)
#' ml <- getMLsoln(0.5, e$Kva, e$y, e$X)
getMLsoln <-
    function(hsq, Kva, y, X, reml=TRUE, use_cpp=TRUE)
{
    n <- length(Kva)
    if(!is.matrix(X)) X <- as.matrix(X)
    stopifnot(nrow(X) == n)
    if(!is.matrix(y)) y <- as.matrix(y)
    stopifnot(nrow(y) == n)
    p <- ncol(X)

    if(use_cpp) {
        result <- Rcpp_getMLsoln(hsq, Kva, y, X, reml)
        tmp <- list(beta=result$beta, sigmasq=result$sigmasq)
        attr(tmp, "rss") <- result$rss
        if(reml) attr(tmp, "logdetXSX") <- result$logdetXSX
        return(tmp)
    }

    # diagonal matrix of weights
    S = 1/(hsq*Kva + 1-hsq)

    # calculate a bunch of matrices
    XSt = t(X * S)     # (XS)'
    ySt = t(y * S)     # (yS)'
    XSX = XSt %*% X    # (XS)'X
    XSy = XSt %*% y    # (XS)'y
    ySy = ySt %*% y    # (yS)'y

    # estimate of beta, by weighted LS
    e <- eigen(XSX)
    evals <- e$values
    evecs <- t(e$vectors)
    if(reml) logdetXSX <- sum(log(evals))
    beta <- t(evecs/evals) %*% evecs %*% XSy

    rss = ySy - t(XSy) %*% beta

    # estimate of sigma^2 (total variance = sigma_g^2 + sigma_e^2)
    sigmasq <- rss / (n - p)

    # return value
    result <- list(beta=beta, sigmasq=sigmasq)
    attr(result, "rss") <- rss
    if(reml) attr(result, "logdetXSX") <- logdetXSX

    result
}

#' Calculate log likelihood for a given heritability
#'
#' Calculate the log likelihood for a given value of the heritability, `hsq`.
#'
#' @param hsq heritability
#' @param Kva eigenvalues of K (calculated by [eigen_rotation()])
#' @param y rotated phenotypes (calculated by [eigen_rotation()])
#' @param X rotated covariate matrix (calculated by [eigen_rotation()])
#' @param reml If TRUE, use REML; otherwise use ordinary maximum likelihood.
#' @param use_cpp = if TRUE, use c++ version of code
#'
#' @export
#' @return The log likelihood value, with the corresponding estimates
#' of `beta` and `sigmasq` included as attributes.
#'
#' @examples
#' data(recla)
#' e <- eigen_rotation(recla$kinship, recla$pheno[,1], recla$covar)
#' loglik <- calcLL(0.5, e$Kva, e$y, e$X)
#' many_loglik <- calcLL(seq(0, 1, by=0.1), e$Kva, e$y, e$X)
calcLL <-
    function(hsq, Kva, y, X, reml=TRUE, use_cpp=TRUE)
{
    if(length(hsq) > 1)
        return(vapply(hsq, calcLL, 0, Kva, y, X, reml, use_cpp))

    if(use_cpp) {
        logdetXpX <- NA
        if(reml) {
            logdetXpX <- attr(X, "logdetXpX")
            if(is.null(logdetXpX))
                logdetXpX <- Rcpp_calc_logdetXpX(X)
        }
        result <- Rcpp_calcLL(hsq, Kva, y, X, reml, logdetXpX)
        tmp <- result$loglik
        attr(tmp, "beta") <- result$beta
        attr(tmp, "sigmasq") <- result$sigmasq
        return(tmp)
    }

    n <- nrow(X)
    p <- ncol(X)

    # estimate beta and sigmasq
    MLsoln <- getMLsoln(hsq, Kva, y, X, reml=reml, use_cpp=use_cpp)
    beta <- MLsoln$beta
    sigmasq <- MLsoln$sigmasq

    # calculate log likelihood
    rss <- attr(MLsoln, "rss")
    LL <- -0.5*(sum(log(hsq*Kva + 1-hsq)) + n*log(rss))

    if(reml) { # note that default is determinant() gives log det
        logdetXpX <- attr(X, "logdetXpX")
        if(is.null(logdetXpX)) { # need to calculate it
            XpX <- t(X) %*% X
            logdetXpX <- sum(log(eigen(XpX)$values))
        }

        logdetXSX <- attr(MLsoln, "logdetXSX")
        LL <- LL + 0.5 * (p*log(2*pi*sigmasq) + logdetXpX - logdetXSX)
    }

    attr(LL, "beta") <- beta
    attr(LL, "sigmasq") <- sigmasq
    LL
}

#' Fit a linear mixed model
#'
#' Fit a linear mixed model of the form y = Xb + e where e follows a
#' multivariate normal distribution with mean 0 and variance matrix
#' `sigmasq_g K + sigmasq_e I`, where `K` is a known kniship
#' matrix and `I` is the identity matrix.
#'
#' @param Kva Eigenvalues of K (calculated by [eigen_rotation()])
#' @param y Rotated phenotypes (calculated by [eigen_rotation()])
#' @param X Rotated covariate matrix (calculated by [eigen_rotation()])
#' @param reml If TRUE, use REML; otherwise use ordinary maximum likelihood.
#' @param check_boundary If TRUE, explicitly check log likelihood at 0 and 1.
#' @param tol Tolerance for convergence
#' @param use_cpp = if TRUE, use c++ version of code
#' @param compute_se = if TRUE, return the standard error of the `hsq`
#' estimate using the Fisher Information matrix of the MLE estimate. The
#' standard error will be in an `attr` of  `hsq` in the output.
#' Currently requires `use_cpp = FALSE`, and so if `compute_se=TRUE`
#' we take `use_cpp=FALSE`.
#'
#' @importFrom stats optim
#'
#' @export
#' @return List containing estimates of `beta`, `sigmasq`,
#' `hsq`, `sigmasq_g`, and `sigmasq_e`, as well as the log
#' likelihood (`loglik`). If `compute_se=TRUE`, the output also
#' contains `hsq_se`.
#'
#' @examples
#' data(recla)
#' e <- eigen_rotation(recla$kinship, recla$pheno[,1], recla$covar)
#' result <- fitLMM(e$Kva, e$y, e$X)
#'
#' # also compute SE
#' wSE <- fitLMM(e$Kva, e$y, e$X, compute_se = TRUE, use_cpp=FALSE)
#' c(hsq=wSE$hsq, SE=wSE$hsq_se)
#'
fitLMM <-
    function(Kva, y, X, reml=TRUE, check_boundary=TRUE, tol=1e-4, use_cpp=TRUE, compute_se = FALSE)
{
    n <- length(Kva)
    if(!is.matrix(X)) X <- as.matrix(X)
    stopifnot(nrow(X) == n)
    if(!is.matrix(y)) y <- as.matrix(y)
    stopifnot(nrow(y) == n)

    if(compute_se && use_cpp) {
        use_cpp <- FALSE
        warning("If compute_se=TRUE, we need to take use_cpp to be FALSE")
    }

    if(use_cpp) {
        logdetXpX <- NA
        if(reml) logdetXpX <- Rcpp_calc_logdetXpX(X)
        result <- Rcpp_fitLMM(Kva, y, X, reml, check_boundary, logdetXpX, tol)
        return(list(beta=result$beta,
                    sigmasq=result$sigmasq,
                    hsq=result$hsq,
                    sigmasq_g=result$hsq*result$sigmasq,
                    sigmasq_e=(1-result$hsq)*result$sigmasq,
                    loglik=result$loglik))
    }

    # calculate log determinant of X'X matrix, so it's only done once
    if(reml) {
        XpX <- t(X) %*% X
        attr(X, "logdetXpX") <- sum(log( eigen(XpX)$values ))
    }

    # maximize log likelihood
    out <- stats::optimize(calcLL, c(0, 1), Kva=Kva, y=y, X=X, reml=reml, use_cpp=use_cpp,
                           maximum=TRUE, tol=tol)

    # Use the hessian to get the stanard errors; had to use `optim` here...
    if(compute_se){
      calcLL2 <- function(hsq, Kva, y, X, reml, use_cpp){
        return(-1*calcLL(hsq, Kva, y, X, reml, use_cpp))
      }
      opt2 <- optim(out$maximum, calcLL2, Kva=Kva, y=y, X=X, reml=reml, use_cpp=use_cpp,
                           hessian=TRUE, lower = 0, upper = 1, method = "Brent")
      vc <- solve(opt2$hessian) # var-cov matrix
      se <- sqrt(diag(vc))        # standard errors
    }

    hsq <- out$maximum
    obj <- out$objective
    sigmasq <- attr(obj, "sigmasq")

    result <- list(beta=attr(obj, "beta"),
                   sigmasq=sigmasq, # total var
                   hsq=hsq,
                   sigmasq_g= hsq*sigmasq, # genetic variance
                   sigmasq_e = (1-hsq)*sigmasq, # residual variance
                   loglik = as.numeric(obj))
    if(compute_se) result$hsq_se <- se

    result
}
